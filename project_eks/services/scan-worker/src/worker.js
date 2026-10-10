const { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');
const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');
const crypto = require('crypto');
const axios = require('axios');
const FormData = require('form-data');
const { Readable } = require('stream');
const Redis = require('ioredis');
const { Client: OpenSearchClient } = require('@opensearch-project/opensearch');
const pino = require('pino');

// Logger
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: process.env.NODE_ENV !== 'production' ? {
    target: 'pino-pretty',
    options: { colorize: true }
  } : undefined
});

// AWS Clients
const sqsClient = new SQSClient({ region: process.env.AWS_REGION || 'us-east-1' });
const s3Client = new S3Client({ region: process.env.AWS_REGION || 'us-east-1' });
const snsClient = new SNSClient({ region: process.env.AWS_REGION || 'us-east-1' });

// Redis Client
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT || '6379'),
  tls: process.env.REDIS_TLS === 'true' ? {} : undefined,
  retryStrategy(times) {
    const delay = Math.min(times * 50, 2000);
    return delay;
  }
});

// OpenSearch Client
const osClient = new OpenSearchClient({
  node: process.env.OPENSEARCH_ENDPOINT,
  auth: {
    username: process.env.OPENSEARCH_USERNAME,
    password: process.env.OPENSEARCH_PASSWORD
  },
  ssl: {
    rejectUnauthorized: true
  }
});

// Configuration
const CONFIG = {
  queueUrl: process.env.SQS_QUEUE_URL,
  maxMessages: parseInt(process.env.SQS_MAX_MESSAGES || '10'),
  waitTimeSeconds: parseInt(process.env.SQS_WAIT_TIME_SECONDS || '20'),
  visibilityTimeout: parseInt(process.env.SQS_VISIBILITY_TIMEOUT || '300'),
  uploadBucket: process.env.S3_UPLOAD_BUCKET,
  quarantineBucket: process.env.S3_QUARANTINE_BUCKET,
  vtApiKey: process.env.VT_API_KEY,
  scanTimeout: parseInt(process.env.SCAN_TIMEOUT || '300') * 1000,
  cacheHashTtl: 86400, // 24 hours
  criticalThreshold: 30, // positives threshold for critical alert
};

// Metrics
const metrics = {
  scansProcessed: 0,
  scansFailed: 0,
  threatsDetected: 0,
  cacheHits: 0,
  cacheMisses: 0
};

class ScanWorker {
  constructor() {
    this.isRunning = false;
    this.podName = process.env.POD_NAME || 'unknown';
  }

  async start() {
    this.isRunning = true;
    logger.info({ pod: this.podName }, 'Scan worker started');

    while (this.isRunning) {
      try {
        await this.pollQueue();
      } catch (error) {
        logger.error({ error: error.message }, 'Error in poll loop');
        await this.sleep(5000);
      }
    }
  }

  async pollQueue() {
    const command = new ReceiveMessageCommand({
      QueueUrl: CONFIG.queueUrl,
      MaxNumberOfMessages: CONFIG.maxMessages,
      WaitTimeSeconds: CONFIG.waitTimeSeconds,
      VisibilityTimeout: CONFIG.visibilityTimeout,
      MessageAttributeNames: ['All']
    });

    const response = await sqsClient.send(command);

    if (!response.Messages || response.Messages.length === 0) {
      return;
    }

    logger.info({ count: response.Messages.length }, 'Received messages from queue');

    await Promise.all(
      response.Messages.map(message => this.processMessage(message))
    );
  }

  async processMessage(message) {
    const startTime = Date.now();
    let scanData;

    try {
      scanData = JSON.parse(message.Body);
      logger.info({ scanId: scanData.scanId, fileName: scanData.fileName }, 'Processing scan');

      const result = await this.scanFile(scanData);

      // Index to OpenSearch
      await this.indexScanResult(result);

      // Delete message from queue
      await this.deleteMessage(message.ReceiptHandle);

      metrics.scansProcessed++;
      
      const duration = Date.now() - startTime;
      logger.info({ 
        scanId: scanData.scanId, 
        positives: result.positives,
        duration 
      }, 'Scan completed');

      // Send alert for critical threats
      if (result.positives >= CONFIG.criticalThreshold) {
        await this.sendCriticalAlert(result);
      }

    } catch (error) {
      metrics.scansFailed++;
      logger.error({ 
        error: error.message, 
        scanId: scanData?.scanId 
      }, 'Scan failed');
      
      // Message will return to queue after visibility timeout
    }
  }

  async scanFile(scanData) {
    const { fileName, fileKey, scanId, userId } = scanData;

    try {
      // Download file from S3
      const fileBuffer = await this.downloadFromS3(fileKey);
      
      // Calculate hash
      const fileHash = crypto.createHash('sha256').update(fileBuffer).digest('hex');

      // Check cache
      const cachedResult = await this.getCachedScan(fileHash);
      if (cachedResult) {
        metrics.cacheHits++;
        logger.info({ fileHash, scanId }, 'Cache hit');
        return {
          ...cachedResult,
          scanId,
          fileName,
          userId,
          cached: true,
          timestamp: new Date().toISOString()
        };
      }

      metrics.cacheMisses++;

      // Scan with VirusTotal
      const vtResult = await this.scanWithVirusTotal(fileBuffer, fileName, fileHash);

      // Cache result
      await this.cacheScanResult(fileHash, vtResult);

      // Quarantine if malicious
      if (vtResult.positives > 0) {
        await this.quarantineFile(fileKey, fileName, fileHash);
        metrics.threatsDetected++;
      }

      return {
        scanId,
        fileName,
        fileHash,
        fileSize: fileBuffer.length,
        userId,
        ...vtResult,
        cached: false,
        timestamp: new Date().toISOString(),
        worker: this.podName
      };

    } catch (error) {
      throw new Error(`Scan failed: ${error.message}`);
    }
  }

  async downloadFromS3(fileKey) {
    const command = new GetObjectCommand({
      Bucket: CONFIG.uploadBucket,
      Key: fileKey
    });

    const response = await s3Client.send(command);
    const chunks = [];
    
    for await (const chunk of response.Body) {
      chunks.push(chunk);
    }

    return Buffer.concat(chunks);
  }

  async scanWithVirusTotal(fileBuffer, fileName, fileHash) {
    // First, check if hash exists in VT
    try {
      const hashResponse = await axios.get(
        `https://www.virustotal.com/api/v3/files/${fileHash}`,
        {
          headers: { 'x-apikey': CONFIG.vtApiKey },
          timeout: 10000
        }
      );

      const data = hashResponse.data.data.attributes;
      return {
        positives: data.last_analysis_stats.malicious,
        total: Object.keys(data.last_analysis_results).length,
        scans: data.last_analysis_results,
        permalink: `https://www.virustotal.com/gui/file/${fileHash}`,
        scanDate: data.last_analysis_date
      };
    } catch (error) {
      if (error.response?.status !== 404) {
        throw error;
      }
    }

    // File not in VT database, upload for scanning
    const formData = new FormData();
    formData.append('file', fileBuffer, fileName);

    const uploadResponse = await axios.post(
      'https://www.virustotal.com/api/v3/files',
      formData,
      {
        headers: {
          ...formData.getHeaders(),
          'x-apikey': CONFIG.vtApiKey
        },
        maxBodyLength: Infinity,
        timeout: 60000
      }
    );

    const analysisId = uploadResponse.data.data.id;

    // Poll for results
    let attempts = 0;
    const maxAttempts = 30;

    while (attempts < maxAttempts) {
      await this.sleep(10000); // Wait 10 seconds

      try {
        const analysisResponse = await axios.get(
          `https://www.virustotal.com/api/v3/analyses/${analysisId}`,
          {
            headers: { 'x-apikey': CONFIG.vtApiKey },
            timeout: 10000
          }
        );

        const status = analysisResponse.data.data.attributes.status;

        if (status === 'completed') {
          const stats = analysisResponse.data.data.attributes.stats;
          const results = analysisResponse.data.data.attributes.results;

          return {
            positives: stats.malicious,
            total: Object.keys(results).length,
            scans: results,
            permalink: `https://www.virustotal.com/gui/file/${fileHash}`,
            scanDate: new Date().toISOString()
          };
        }
      } catch (error) {
        logger.warn({ error: error.message, attempt: attempts }, 'Analysis poll failed');
      }

      attempts++;
    }

    throw new Error('VirusTotal scan timeout');
  }

  async getCachedScan(fileHash) {
    const cached = await redis.get(`scan:${fileHash}`);
    return cached ? JSON.parse(cached) : null;
  }

  async cacheScanResult(fileHash, result) {
    await redis.setex(
      `scan:${fileHash}`,
      CONFIG.cacheHashTtl,
      JSON.stringify(result)
    );
  }

  async quarantineFile(fileKey, fileName, fileHash) {
    const command = new GetObjectCommand({
      Bucket: CONFIG.uploadBucket,
      Key: fileKey
    });

    const response = await s3Client.send(command);
    const chunks = [];
    
    for await (const chunk of response.Body) {
      chunks.push(chunk);
    }

    const putCommand = new PutObjectCommand({
      Bucket: CONFIG.quarantineBucket,
      Key: `${fileHash}/${fileName}`,
      Body: Buffer.concat(chunks),
      Metadata: {
        originalKey: fileKey,
        quarantinedAt: new Date().toISOString(),
        fileHash
      }
    });

    await s3Client.send(putCommand);
    logger.info({ fileName, fileHash }, 'File quarantined');
  }

  async indexScanResult(result) {
    await osClient.index({
      index: 'scans',
      id: result.scanId,
      body: {
        ...result,
        riskLevel: this.calculateRiskLevel(result.positives),
        indexed_at: new Date().toISOString()
      }
    });
  }

  calculateRiskLevel(positives) {
    if (positives === 0) return 'safe';
    if (positives < 5) return 'low';
    if (positives < 15) return 'medium';
    if (positives < 30) return 'high';
    return 'critical';
  }

  async sendCriticalAlert(result) {
    const command = new PublishCommand({
      TopicArn: process.env.SNS_CRITICAL_THREATS_ARN,
      Subject: `Critical Threat Detected: ${result.fileName}`,
      Message: JSON.stringify({
        fileName: result.fileName,
        fileHash: result.fileHash,
        positives: result.positives,
        total: result.total,
        riskLevel: 'critical',
        scanId: result.scanId,
        timestamp: result.timestamp,
        permalink: result.permalink
      }, null, 2)
    });

    await snsClient.send(command);
    logger.warn({ scanId: result.scanId }, 'Critical alert sent');
  }

  async deleteMessage(receiptHandle) {
    const command = new DeleteMessageCommand({
      QueueUrl: CONFIG.queueUrl,
      ReceiptHandle: receiptHandle
    });

    await sqsClient.send(command);
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async stop() {
    this.isRunning = false;
    logger.info('Stopping scan worker...');
    await redis.quit();
    logger.info('Scan worker stopped');
  }
}

// Graceful shutdown
const worker = new ScanWorker();

process.on('SIGTERM', async () => {
  logger.info('SIGTERM received');
  await worker.stop();
  process.exit(0);
});

process.on('SIGINT', async () => {
  logger.info('SIGINT received');
  await worker.stop();
  process.exit(0);
});

// Start worker
worker.start().catch(error => {
  logger.fatal({ error: error.message }, 'Worker crashed');
  process.exit(1);
});

// Expose metrics
setInterval(() => {
  logger.info({
    metrics: {
      ...metrics,
      cacheHitRate: metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses) || 0
    }
  }, 'Worker metrics');
}, 60000);
