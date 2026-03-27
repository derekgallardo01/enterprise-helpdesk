/**
 * k6 Load Test: Dashboard / Health Check Endpoint
 *
 * Simulates dashboard load by hitting the /api/health endpoint
 * under increasing concurrency.
 *
 * Stages:
 *   - Ramp to 50 VUs over 1 minute
 *   - Sustain 100 VUs for 3 minutes
 *   - Ramp down to 0 over 1 minute
 *
 * Thresholds:
 *   - p95 response time < 2 seconds
 *   - Error rate < 1%
 *
 * Usage:
 *   k6 run dashboard-load.js
 *   k6 run --env BASE_URL=https://helpdesk-functions-test.azurewebsites.net dashboard-load.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const healthCheckDuration = new Trend('health_check_duration', true);

// Configuration
const BASE_URL = __ENV.BASE_URL || 'https://helpdesk-functions-test.azurewebsites.net';

export const options = {
    stages: [
        { duration: '1m', target: 50 },   // Ramp up to 50 VUs
        { duration: '3m', target: 100 },   // Sustain 100 VUs
        { duration: '1m', target: 0 },     // Ramp down
    ],
    thresholds: {
        http_req_duration: ['p(95)<2000'],  // p95 < 2 seconds
        errors: ['rate<0.01'],              // Error rate < 1%
    },
    tags: {
        testName: 'dashboard-load',
    },
};

export default function () {
    const url = `${BASE_URL}/api/health`;

    const params = {
        headers: {
            'Accept': 'application/json',
        },
        tags: { endpoint: 'health' },
    };

    const response = http.get(url, params);

    // Track custom metric
    healthCheckDuration.add(response.timings.duration);

    // Validate response
    const success = check(response, {
        'status is 200 or 503': (r) => r.status === 200 || r.status === 503,
        'response has status field': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.status !== undefined;
            } catch {
                return false;
            }
        },
        'response has dataverse field': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.dataverse !== undefined;
            } catch {
                return false;
            }
        },
        'response has sql field': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.sql !== undefined;
            } catch {
                return false;
            }
        },
        'response time < 2s': (r) => r.timings.duration < 2000,
    });

    errorRate.add(!success);

    // Simulate user think time between dashboard refreshes
    sleep(Math.random() * 2 + 1); // 1-3 seconds
}

export function handleSummary(data) {
    const summary = {
        testName: 'Dashboard Load Test',
        timestamp: new Date().toISOString(),
        totalRequests: data.metrics.http_reqs.values.count,
        avgResponseTime: Math.round(data.metrics.http_req_duration.values.avg),
        p95ResponseTime: Math.round(data.metrics.http_req_duration.values['p(95)']),
        p99ResponseTime: Math.round(data.metrics.http_req_duration.values['p(99)']),
        errorRate: (data.metrics.errors?.values?.rate || 0) * 100,
        thresholdsPassed: !data.root_group?.checks?.some(c => c.fails > 0),
    };

    console.log('\n=== Dashboard Load Test Summary ===');
    console.log(`Total Requests:    ${summary.totalRequests}`);
    console.log(`Avg Response Time: ${summary.avgResponseTime}ms`);
    console.log(`p95 Response Time: ${summary.p95ResponseTime}ms`);
    console.log(`p99 Response Time: ${summary.p99ResponseTime}ms`);
    console.log(`Error Rate:        ${summary.errorRate.toFixed(2)}%`);
    console.log('===================================\n');

    return {
        'stdout': JSON.stringify(summary, null, 2) + '\n',
        'results/dashboard-load-results.json': JSON.stringify(summary, null, 2),
    };
}
