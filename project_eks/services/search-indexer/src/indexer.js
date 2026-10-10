const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { Client } = require('@opensearch-project/opensearch');
const Redis = require('ioredis');
const pino = require('pino');
const pinoHttp = require('pino-http');

// Logger
const logger = pino({
  level: process.env.LOG_LEVEL || 'info'
});

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(pinoHttp({ logger }));

// OpenSearch Client
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

// Redis Client for caching
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: parseInt(process.env.REDIS_PORT || '6379'),
  tls: process.env.REDIS_TLS === 'true' ? {} : undefined
});

// Search Service
class SearchService {
  constructor() {
    this.scanIndex = 'scans';
    this.secretIndex = 'secrets';
    this.threatIndex = 'threats';
  }

  // Full-text search across all scans
  async searchScans(query, filters = {}, options = {}) {
    const must = [];
    const filter = [];

    // Text search
    if (query) {
      must.push({
        multi_match: {
          query: query,
          fields: ['fileName^3', 'threats', 'aiSummary', 'fileHash'],
          type: 'best_fields',
          fuzziness: 'AUTO'
        }
      });
    }

    // Filters
    if (filters.riskLevel) {
      filter.push({ term: { riskLevel: filters.riskLevel } });
    }

    if (filters.userId) {
      filter.push({ term: { userId: filters.userId } });
    }

    if (filters.dateRange) {
      filter.push({
        range: {
          timestamp: {
            gte: filters.dateRange.start,
            lte: filters.dateRange.end
          }
        }
      });
    }

    if (filters.minPositives !== undefined) {
      filter.push({
        range: {
          positives: { gte: filters.minPositives }
        }
      });
    }

    const body = {
      query: {
        bool: {
          must: must.length > 0 ? must : [{ match_all: {} }],
          filter: filter.length > 0 ? filter : undefined
        }
      },
      sort: options.sort || [{ timestamp: 'desc' }],
      from: options.from || 0,
      size: options.size || 20,
      highlight: {
        fields: {
          fileName: {},
          threats: {},
          aiSummary: {}
        },
        pre_tags: ['<mark>'],
        post_tags: ['</mark>']
      }
    };

    const response = await osClient.search({
      index: this.scanIndex,
      body
    });

    return {
      total: response.body.hits.total.value,
      results: response.body.hits.hits.map(hit => ({
        id: hit._id,
        score: hit._score,
        ...hit._source,
        highlights: hit.highlight
      }))
    };
  }

  // Aggregations for analytics dashboard
  async getAnalytics(timeRange = '30d') {
    const response = await osClient.search({
      index: this.scanIndex,
      body: {
        size: 0,
        query: {
          range: {
            timestamp: { gte: `now-${timeRange}` }
          }
        },
        aggs: {
          risk_distribution: {
            terms: {
              field: 'riskLevel',
              size: 10
            }
          },
          top_threats: {
            terms: {
              field: 'threats.keyword',
              size: 20
            }
          },
          scans_over_time: {
            date_histogram: {
              field: 'timestamp',
              calendar_interval: 'day',
              format: 'yyyy-MM-dd'
            },
            aggs: {
              avg_positives: {
                avg: { field: 'positives' }
              }
            }
          },
          avg_scan_positives: {
            avg: { field: 'positives' }
          },
          total_threats: {
            sum: { field: 'positives' }
          },
          unique_users: {
            cardinality: { field: 'userId' }
          }
        }
      }
    });

    return response.body.aggregations;
  }

  // Search for similar files by hash
  async findSimilarScans(fileHash) {
    const response = await osClient.search({
      index: this.scanIndex,
      body: {
        query: {
          term: { fileHash: fileHash }
        },
        size: 10,
        sort: [{ timestamp: 'desc' }]
      }
    });

    return response.body.hits.hits.map(hit => hit._source);
  }

  // Get scan by ID
  async getScanById(scanId) {
    try {
      const response = await osClient.get({
        index: this.scanIndex,
        id: scanId
      });

      return response.body._source;
    } catch (error) {
      if (error.meta?.statusCode === 404) {
        return null;
      }
      throw error;
    }
  }

  // Auto-complete suggestions
  async getSuggestions(prefix, field = 'fileName') {
    const response = await osClient.search({
      index: this.scanIndex,
      body: {
        size: 0,
        suggest: {
          suggestions: {
            prefix: prefix,
            completion: {
              field: `${field}.suggest`,
              size: 10,
              skip_duplicates: true
            }
          }
        }
      }
    });

    return response.body.suggest.suggestions[0].options.map(opt => opt.text);
  }

  // Faceted search
  async getFacets() {
    const response = await osClient.search({
      index: this.scanIndex,
      body: {
        size: 0,
        aggs: {
          risk_levels: {
            terms: { field: 'riskLevel', size: 10 }
          },
          file_types: {
            terms: { field: 'fileType.keyword', size: 20 }
          },
          scan_sources: {
            terms: { field: 'worker', size: 50 }
          }
        }
      }
    });

    return response.body.aggregations;
  }

  // Threat intelligence - most dangerous threats
  async getThreatIntelligence() {
    const response = await osClient.search({
      index: this.scanIndex,
      body: {
        size: 0,
        query: {
          range: {
            positives: { gte: 10 }
          }
        },
        aggs: {
          dangerous_threats: {
            terms: {
              field: 'threats.keyword',
              size: 50,
              order: { _count: 'desc' }
            }
          },
          threat_trends: {
            date_histogram: {
              field: 'timestamp',
              calendar_interval: 'week'
            },
            aggs: {
              avg_severity: {
                avg: { field: 'positives' }
              }
            }
          }
        }
      }
    });

    return response.body.aggregations;
  }
}

const searchService = new SearchService();

// Routes

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'search-indexer' });
});

app.get('/ready', async (req, res) => {
  try {
    await osClient.ping();
    await redis.ping();
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

// Search scans
app.post('/search', async (req, res) => {
  try {
    const { query, filters, options } = req.body;

    // Check cache
    const cacheKey = `search:${JSON.stringify({ query, filters, options })}`;
    const cached = await redis.get(cacheKey);

    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const results = await searchService.searchScans(query, filters, options);

    // Cache for 5 minutes
    await redis.setex(cacheKey, 300, JSON.stringify(results));

    res.json(results);
  } catch (error) {
    logger.error({ error: error.message }, 'Search failed');
    res.status(500).json({ error: 'Search failed', details: error.message });
  }
});

// Get analytics
app.get('/analytics', async (req, res) => {
  try {
    const timeRange = req.query.timeRange || '30d';

    const cacheKey = `analytics:${timeRange}`;
    const cached = await redis.get(cacheKey);

    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const analytics = await searchService.getAnalytics(timeRange);

    // Cache for 10 minutes
    await redis.setex(cacheKey, 600, JSON.stringify(analytics));

    res.json(analytics);
  } catch (error) {
    logger.error({ error: error.message }, 'Analytics failed');
    res.status(500).json({ error: 'Analytics failed', details: error.message });
  }
});

// Get scan by ID
app.get('/scans/:scanId', async (req, res) => {
  try {
    const scan = await searchService.getScanById(req.params.scanId);

    if (!scan) {
      return res.status(404).json({ error: 'Scan not found' });
    }

    res.json(scan);
  } catch (error) {
    logger.error({ error: error.message }, 'Get scan failed');
    res.status(500).json({ error: 'Failed to get scan', details: error.message });
  }
});

// Find similar scans
app.get('/scans/:fileHash/similar', async (req, res) => {
  try {
    const similar = await searchService.findSimilarScans(req.params.fileHash);
    res.json({ count: similar.length, scans: similar });
  } catch (error) {
    logger.error({ error: error.message }, 'Similar scans failed');
    res.status(500).json({ error: 'Failed to find similar scans', details: error.message });
  }
});

// Auto-complete suggestions
app.get('/suggest', async (req, res) => {
  try {
    const { q, field } = req.query;

    if (!q) {
      return res.status(400).json({ error: 'Query parameter q is required' });
    }

    const suggestions = await searchService.getSuggestions(q, field);
    res.json({ suggestions });
  } catch (error) {
    logger.error({ error: error.message }, 'Suggestions failed');
    res.status(500).json({ error: 'Failed to get suggestions', details: error.message });
  }
});

// Get facets
app.get('/facets', async (req, res) => {
  try {
    const cacheKey = 'facets:all';
    const cached = await redis.get(cacheKey);

    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const facets = await searchService.getFacets();

    // Cache for 15 minutes
    await redis.setex(cacheKey, 900, JSON.stringify(facets));

    res.json(facets);
  } catch (error) {
    logger.error({ error: error.message }, 'Facets failed');
    res.status(500).json({ error: 'Failed to get facets', details: error.message });
  }
});

// Threat intelligence
app.get('/threat-intelligence', async (req, res) => {
  try {
    const cacheKey = 'threat-intelligence';
    const cached = await redis.get(cacheKey);

    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const intelligence = await searchService.getThreatIntelligence();

    // Cache for 1 hour
    await redis.setex(cacheKey, 3600, JSON.stringify(intelligence));

    res.json(intelligence);
  } catch (error) {
    logger.error({ error: error.message }, 'Threat intelligence failed');
    res.status(500).json({ error: 'Failed to get threat intelligence', details: error.message });
  }
});

// Start server
app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Search indexer service started');
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, shutting down gracefully');
  await redis.quit();
  process.exit(0);
});
