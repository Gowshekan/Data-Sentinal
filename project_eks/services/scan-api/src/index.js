const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const multer = require('multer');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const { v4: uuidv4 } = require('uuid');
const Redis = require('ioredis');
const pino = require('pino');
const pinoHttp = require('pino-http');
const rateLimit = require('express-rate-limit');

// Logger
const logger = pino({
  level: process.env.LOG_LEVEL || 'info'
});

const app = express();
const PORT = process.env.PORT || 5000;

// AWS Clients
const s3Client = new S3Client({ region: process.env.AWS_REGION || 'us-east-1' });
const sqsClient = new SQSClient({ region: process.env.AWS_REGION || 'us-east-1' });

// Redis Client
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT || '6379'),
  tls: process.env.REDIS_TLS === 'true' ? {} : undefined
});

// Multer configuration for file uploads
const storage = multer.memoryStorage();
const upload = multer({
  storage,
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE || '104857600') // 100MB
  },
  fileFilter: (req, file, cb) => {
    // Accept all files, but log suspicious extensions
    const suspiciousExts = ['.exe', '.dll', '.bat', '.cmd', '.sh', '.ps1'];
    const ext = file.originalname.toLowerCase().substring(file.originalname.lastIndexOf('.'));
    
    if (suspiciousExts.includes(ext)) {
      logger.warn({ fileName: file.originalname }, 'Suspicious file upload');
    }
    
    cb(null, true);
  }
});

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW || '900000'), // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100'),
  message: 'Too many requests from this IP, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn({ ip: req.ip }, 'Rate limit exceeded');
    res.status(429).json({
      error: 'Too many requests',
      message: 'Please try again later'
    });
  }
});

app.use('/api/', limiter);

// Health checks
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'scan-api', timestamp: new Date().toISOString() });
});

app.get('/ready', async (req, res) => {
  try {
    await redis.ping();
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

// Upload and queue file for scanning
app.post('/api/scan/file', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const scanId = uuidv4();
    const userId = req.headers['x-user-id'] || 'anonymous';
    const fileKey = `uploads/${userId}/${scanId}/${req.file.originalname}`;

    // Upload to S3
    const uploadCommand = new PutObjectCommand({
      Bucket: process.env.S3_UPLOAD_BUCKET,
      Key: fileKey,
      Body: req.file.buffer,
      ContentType: req.file.mimetype,
      Metadata: {
        originalName: req.file.originalname,
        uploadedBy: userId,
        scanId: scanId,
        uploadedAt: new Date().toISOString()
      }
    });

    await s3Client.send(uploadCommand);

    // Queue scan job
    const messageBody = {
      scanId,
      fileName: req.file.originalname,
      fileKey,
      fileSize: req.file.size,
      userId,
      timestamp: new Date().toISOString()
    };

    const sqsCommand = new SendMessageCommand({
      QueueUrl: process.env.SQS_QUEUE_URL,
      MessageBody: JSON.stringify(messageBody),
      MessageAttributes: {
        scanId: {
          DataType: 'String',
          StringValue: scanId
        },
        userId: {
          DataType: 'String',
          StringValue: userId
        }
      }
    });

    await sqsClient.send(sqsCommand);

    logger.info({ scanId, fileName: req.file.originalname, userId }, 'File queued for scanning');

    res.status(202).json({
      message: 'File uploaded and queued for scanning',
      scanId,
      fileName: req.file.originalname,
      fileSize: req.file.size,
      status: 'queued'
    });

  } catch (error) {
    logger.error({ error: error.message }, 'File upload failed');
    res.status(500).json({
      error: 'Failed to upload file',
      details: error.message
    });
  }
});

// Get scan status
app.get('/api/scan/:scanId', async (req, res) => {
  try {
    const { scanId } = req.params;

    // Try to get from cache first (for completed scans)
    const cached = await redis.get(`scan:result:${scanId}`);
    
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    // Check if scan is in progress
    const inProgress = await redis.get(`scan:progress:${scanId}`);
    
    if (inProgress) {
      return res.json({
        scanId,
        status: 'processing',
        message: 'Scan in progress'
      });
    }

    // Not found
    res.status(404).json({
      error: 'Scan not found',
      scanId
    });

  } catch (error) {
    logger.error({ error: error.message }, 'Get scan status failed');
    res.status(500).json({
      error: 'Failed to get scan status',
      details: error.message
    });
  }
});

// Get recent scans
app.get('/api/scans', async (req, res) => {
  try {
    const userId = req.headers['x-user-id'] || 'anonymous';
    const limit = parseInt(req.query.limit || '20');

    // This would typically query from database or search indexer
    // For now, return placeholder response
    res.json({
      message: 'Use /api/search endpoint for querying scans',
      searchEndpoint: '/api/search'
    });

  } catch (error) {
    logger.error({ error: error.message }, 'Get scans failed');
    res.status(500).json({
      error: 'Failed to get scans',
      details: error.message
    });
  }
});

// Search scans (proxy to search-indexer service)
app.post('/api/search', async (req, res) => {
  try {
    // This would proxy to search-indexer service
    // Implementation depends on service mesh or direct call
    res.json({
      message: 'Search functionality',
      note: 'Connect to search-indexer service for full functionality'
    });
  } catch (error) {
    logger.error({ error: error.message }, 'Search failed');
    res.status(500).json({
      error: 'Search failed',
      details: error.message
    });
  }
});

// Analytics endpoint
app.get('/api/analytics', async (req, res) => {
  try {
    const userId = req.headers['x-user-id'];

    // Get from cache
    const cacheKey = userId ? `analytics:user:${userId}` : 'analytics:global';
    const cached = await redis.get(cacheKey);

    if (cached) {
      return res.json(JSON.parse(cached));
    }

    // This would query OpenSearch via search-indexer
    res.json({
      message: 'Analytics endpoint',
      note: 'Connect to search-indexer service for analytics'
    });

  } catch (error) {
    logger.error({ error: error.message }, 'Analytics failed');
    res.status(500).json({
      error: 'Failed to get analytics',
      details: error.message
    });
  }
});

// Metrics endpoint for Prometheus
app.get('/metrics', async (req, res) => {
  try {
    // Implement Prometheus metrics here
    res.set('Content-Type', 'text/plain');
    res.send('# Metrics endpoint\n');
  } catch (error) {
    res.status(500).send('Error generating metrics');
  }
});

// Error handler
app.use((error, req, res, next) => {
  logger.error({ error: error.message, stack: error.stack }, 'Unhandled error');
  
  res.status(error.status || 500).json({
    error: error.message || 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { stack: error.stack })
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path
  });
});

// Start server
app.listen(PORT, () => {
  logger.info({ port: PORT, env: process.env.NODE_ENV }, 'Scan API service started');
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, shutting down gracefully');
  await redis.quit();
  process.exit(0);
});

process.on('SIGINT', async () => {
  logger.info('SIGINT received, shutting down gracefully');
  await redis.quit();
  process.exit(0);
});
