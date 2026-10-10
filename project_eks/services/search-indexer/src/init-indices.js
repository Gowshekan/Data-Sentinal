const { Client } = require('@opensearch-project/opensearch');

const osClient = new Client({
  node: process.env.OPENSEARCH_ENDPOINT,
  auth: {
    username: process.env.OPENSEARCH_USERNAME,
    password: process.env.OPENSEARCH_PASSWORD
  },
  ssl: {
    rejectUnauthorized: true
  }
});

async function initializeIndices() {
  console.log('Initializing OpenSearch indices...');

  // Scans Index
  const scansIndexConfig = {
    settings: {
      number_of_shards: 3,
      number_of_replicas: 1,
      'index.refresh_interval': '5s',
      analysis: {
        analyzer: {
          filename_analyzer: {
            type: 'custom',
            tokenizer: 'standard',
            filter: ['lowercase', 'asciifolding']
          }
        }
      }
    },
    mappings: {
      properties: {
        scanId: { type: 'keyword' },
        fileName: { 
          type: 'text',
          analyzer: 'filename_analyzer',
          fields: {
            keyword: { type: 'keyword' },
            suggest: { type: 'completion' }
          }
        },
        fileHash: { type: 'keyword' },
        fileSize: { type: 'long' },
        userId: { type: 'keyword' },
        positives: { type: 'integer' },
        total: { type: 'integer' },
        riskLevel: { type: 'keyword' },
        threats: { 
          type: 'text',
          fields: {
            keyword: { type: 'keyword' }
          }
        },
        aiSummary: { type: 'text' },
        permalink: { type: 'keyword' },
        timestamp: { type: 'date' },
        scanDate: { type: 'date' },
        cached: { type: 'boolean' },
        worker: { type: 'keyword' },
        indexed_at: { type: 'date' }
      }
    }
  };

  try {
    const exists = await osClient.indices.exists({ index: 'scans' });
    
    if (exists.body) {
      console.log('Scans index already exists');
    } else {
      await osClient.indices.create({
        index: 'scans',
        body: scansIndexConfig
      });
      console.log('✓ Scans index created');
    }
  } catch (error) {
    console.error('Failed to create scans index:', error.message);
  }

  // Secrets Index
  const secretsIndexConfig = {
    settings: {
      number_of_shards: 2,
      number_of_replicas: 1
    },
    mappings: {
      properties: {
        secretId: { type: 'keyword' },
        projectPath: { type: 'text' },
        filePath: { type: 'keyword' },
        secretType: { type: 'keyword' },
        lineNumber: { type: 'integer' },
        content: { type: 'text' },
        severity: { type: 'keyword' },
        userId: { type: 'keyword' },
        timestamp: { type: 'date' }
      }
    }
  };

  try {
    const exists = await osClient.indices.exists({ index: 'secrets' });
    
    if (exists.body) {
      console.log('Secrets index already exists');
    } else {
      await osClient.indices.create({
        index: 'secrets',
        body: secretsIndexConfig
      });
      console.log('✓ Secrets index created');
    }
  } catch (error) {
    console.error('Failed to create secrets index:', error.message);
  }

  console.log('Index initialization complete!');
  process.exit(0);
}

initializeIndices().catch(error => {
  console.error('Initialization failed:', error);
  process.exit(1);
});
