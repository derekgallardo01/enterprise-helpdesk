/**
 * k6 Benchmark: DataverseSyncToSQL Timer Function
 *
 * Triggers the DataverseSyncToSQL function via its HTTP admin endpoint
 * and measures the total sync duration. This test is designed to run
 * with a small number of VUs since the sync function processes all
 * pending changes in a single execution.
 *
 * Usage:
 *   k6 run sync-benchmark.js
 *   k6 run --env BASE_URL=https://helpdesk-functions-test.azurewebsites.net \
 *          --env FUNCTION_KEY=your-master-key sync-benchmark.js
 *
 * Note: Timer-triggered functions can be invoked on-demand via the Azure Functions
 * admin API: POST /admin/functions/{functionName} with the master key.
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

// Custom metrics
const syncDuration = new Trend('sync_duration_ms', true);
const syncSuccessCount = new Counter('sync_success');
const syncFailureCount = new Counter('sync_failure');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'https://helpdesk-functions-test.azurewebsites.net';
const FUNCTION_KEY = __ENV.FUNCTION_KEY || '';

export const options = {
    // Run sync sequentially -- only 1 VU to avoid concurrent sync conflicts
    vus: 1,
    iterations: 5,  // Run 5 sync cycles to get a representative average
    thresholds: {
        sync_duration_ms: ['p(95)<60000'],   // p95 sync time < 60 seconds
        sync_failure: ['count<2'],            // Allow at most 1 failure in 5 runs
    },
    tags: {
        testName: 'sync-benchmark',
    },
};

/**
 * Triggers the DataverseSyncToSQL timer function via the admin API.
 *
 * Azure Functions timer triggers can be manually invoked by POSTing to:
 *   POST /admin/functions/DataverseSyncToSQL
 *   Headers: x-functions-key: {master-key}
 *   Body: {}
 *
 * The function runs synchronously and returns when the sync is complete.
 */
export default function () {
    console.log(`Starting sync iteration ${__ITER + 1}...`);

    const url = `${BASE_URL}/admin/functions/DataverseSyncToSQL`;

    const params = {
        headers: {
            'Content-Type': 'application/json',
            'x-functions-key': FUNCTION_KEY,
        },
        tags: { endpoint: 'sync-trigger' },
        timeout: '120s',  // Sync may take up to 2 minutes
    };

    // The admin endpoint expects a JSON body (can be empty for timer triggers)
    const payload = JSON.stringify({ input: '' });

    const startTime = Date.now();
    const response = http.post(url, payload, params);
    const duration = Date.now() - startTime;

    // Track sync duration
    syncDuration.add(duration);

    // Validate response
    const success = check(response, {
        'status is 202 (accepted)': (r) => r.status === 202,
        'sync completed within 2 minutes': () => duration < 120000,
    });

    if (success) {
        syncSuccessCount.add(1);
        console.log(`  Sync iteration ${__ITER + 1} completed in ${duration}ms`);
    } else {
        syncFailureCount.add(1);
        console.log(`  Sync iteration ${__ITER + 1} FAILED (status=${response.status}, duration=${duration}ms)`);
        if (response.body) {
            console.log(`  Response: ${response.body.substring(0, 500)}`);
        }
    }

    // Verify the sync by checking the health endpoint
    const healthResponse = http.get(`${BASE_URL}/api/health`, {
        headers: { 'Accept': 'application/json' },
        tags: { endpoint: 'health-after-sync' },
    });

    check(healthResponse, {
        'health check returns valid response': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.status !== undefined && body.sql !== undefined;
            } catch {
                return false;
            }
        },
        'SQL is healthy after sync': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.sql === true;
            } catch {
                return false;
            }
        },
    });

    // Wait between sync iterations to allow system to stabilize
    sleep(10);
}

export function handleSummary(data) {
    const syncMetrics = data.metrics.sync_duration_ms?.values || {};

    const summary = {
        testName: 'Dataverse Sync Benchmark',
        timestamp: new Date().toISOString(),
        iterations: data.metrics.iterations?.values?.count || 0,
        syncDuration: {
            avg: Math.round(syncMetrics.avg || 0),
            min: Math.round(syncMetrics.min || 0),
            max: Math.round(syncMetrics.max || 0),
            p50: Math.round(syncMetrics['p(50)'] || 0),
            p95: Math.round(syncMetrics['p(95)'] || 0),
            p99: Math.round(syncMetrics['p(99)'] || 0),
        },
        successCount: data.metrics.sync_success?.values?.count || 0,
        failureCount: data.metrics.sync_failure?.values?.count || 0,
    };

    console.log('\n=== Dataverse Sync Benchmark Summary ===');
    console.log(`Iterations:     ${summary.iterations}`);
    console.log(`Success/Fail:   ${summary.successCount}/${summary.failureCount}`);
    console.log(`Avg Duration:   ${summary.syncDuration.avg}ms`);
    console.log(`Min Duration:   ${summary.syncDuration.min}ms`);
    console.log(`Max Duration:   ${summary.syncDuration.max}ms`);
    console.log(`p95 Duration:   ${summary.syncDuration.p95}ms`);
    console.log('=========================================\n');

    return {
        'stdout': JSON.stringify(summary, null, 2) + '\n',
        'results/sync-benchmark-results.json': JSON.stringify(summary, null, 2),
    };
}
