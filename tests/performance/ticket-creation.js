/**
 * k6 Load Test: Ticket Creation via WebhookReceiver
 *
 * Simulates external ITSM systems pushing tickets via the ServiceNow webhook endpoint.
 *
 * Stages:
 *   - Ramp to 20 VUs over 1 minute
 *   - Sustain 50 VUs for 3 minutes
 *   - Ramp down to 0 over 1 minute
 *
 * Thresholds:
 *   - p95 response time < 500ms
 *   - Error rate < 1%
 *
 * Usage:
 *   k6 run ticket-creation.js
 *   k6 run --env BASE_URL=https://helpdesk-functions-test.azurewebsites.net \
 *          --env WEBHOOK_SECRET=your-secret ticket-creation.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { crypto } from 'k6/experimental/webcrypto';

// Custom metrics
const errorRate = new Rate('errors');
const ticketCreationDuration = new Trend('ticket_creation_duration', true);
const ticketsCreated = new Counter('tickets_created');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'https://helpdesk-functions-test.azurewebsites.net';
const WEBHOOK_SECRET = __ENV.WEBHOOK_SECRET || 'test-webhook-secret';

export const options = {
    stages: [
        { duration: '1m', target: 20 },   // Ramp up to 20 VUs
        { duration: '3m', target: 50 },    // Sustain 50 VUs
        { duration: '1m', target: 0 },     // Ramp down
    ],
    thresholds: {
        http_req_duration: ['p(95)<500'],   // p95 < 500ms
        errors: ['rate<0.01'],              // Error rate < 1%
    },
    tags: {
        testName: 'ticket-creation',
    },
};

// Sample categories and descriptions for realistic payloads
const categories = ['Hardware', 'Software', 'Network', 'Email', 'Access'];
const priorities = ['1', '2', '3', '4'];
const descriptions = [
    'User reports laptop is not booting after overnight update.',
    'VPN connection drops every 10 minutes from remote location.',
    'Cannot access shared drive. Permission denied error.',
    'Outlook crashes on startup after latest Office update.',
    'New employee needs Active Directory account and email setup.',
    'Printer on 3rd floor is jamming frequently.',
    'WiFi signal is very weak in conference room B.',
    'Software license expired for Adobe Creative Suite.',
    'MFA token not working after phone replacement.',
    'Monitor flickering when connected to docking station.',
];

/**
 * Generates a unique ServiceNow-style incident number for each request.
 */
function generateIncidentNumber(vuId, iteration) {
    return `INC-PERF-${vuId}-${iteration}-${Date.now()}`;
}

/**
 * Computes HMAC-SHA256 signature for webhook authentication.
 * Note: k6 webcrypto is experimental. If not available, use a pre-shared
 * signature approach or disable HMAC validation in the test environment.
 */
function computeHmacHex(body, secret) {
    // Fallback: use a pre-computed signature approach
    // In production k6 tests, you may need a helper library
    // For now, we use the k6 experimental crypto API
    try {
        const encoder = new TextEncoder();
        const keyData = encoder.encode(secret);
        const msgData = encoder.encode(body);

        // k6 experimental webcrypto
        const key = crypto.subtle.importKeySync(
            'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
        );
        const signature = crypto.subtle.signSync('HMAC', key, msgData);
        const hashArray = new Uint8Array(signature);
        return Array.from(hashArray).map(b => b.toString(16).padStart(2, '0')).join('');
    } catch (e) {
        // If webcrypto is not available, return empty string
        // The test environment should have HMAC validation disabled for load tests
        console.warn('HMAC computation not available. Ensure test environment bypasses signature validation.');
        return '';
    }
}

export default function () {
    const incidentNumber = generateIncidentNumber(__VU, __ITER);
    const category = categories[Math.floor(Math.random() * categories.length)];
    const priority = priorities[Math.floor(Math.random() * priorities.length)];
    const description = descriptions[Math.floor(Math.random() * descriptions.length)];

    const payload = JSON.stringify({
        number: incidentNumber,
        short_description: `[PERF-TEST] ${category} issue - ${incidentNumber}`,
        description: description,
        priority: priority,
        state: '1',
        category: category,
    });

    const signature = computeHmacHex(payload, WEBHOOK_SECRET);

    const params = {
        headers: {
            'Content-Type': 'application/json',
            'X-Webhook-Signature': signature,
        },
        tags: { endpoint: 'webhook-servicenow' },
    };

    const url = `${BASE_URL}/api/webhook/servicenow`;
    const response = http.post(url, payload, params);

    // Track custom metric
    ticketCreationDuration.add(response.timings.duration);

    // Validate response
    const success = check(response, {
        'status is 200': (r) => r.status === 200,
        'response has ticketId': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.ticketId !== undefined;
            } catch {
                return false;
            }
        },
        'response has externalId': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.externalId === incidentNumber;
            } catch {
                return false;
            }
        },
        'response time < 500ms': (r) => r.timings.duration < 500,
    });

    if (success) {
        ticketsCreated.add(1);
    }

    errorRate.add(!success);

    // Simulate interval between webhook deliveries
    sleep(Math.random() * 1 + 0.5); // 0.5-1.5 seconds
}

export function handleSummary(data) {
    const summary = {
        testName: 'Ticket Creation Load Test',
        timestamp: new Date().toISOString(),
        totalRequests: data.metrics.http_reqs.values.count,
        ticketsCreated: data.metrics.tickets_created?.values?.count || 0,
        avgResponseTime: Math.round(data.metrics.http_req_duration.values.avg),
        p95ResponseTime: Math.round(data.metrics.http_req_duration.values['p(95)']),
        p99ResponseTime: Math.round(data.metrics.http_req_duration.values['p(99)']),
        errorRate: (data.metrics.errors?.values?.rate || 0) * 100,
    };

    console.log('\n=== Ticket Creation Load Test Summary ===');
    console.log(`Total Requests:    ${summary.totalRequests}`);
    console.log(`Tickets Created:   ${summary.ticketsCreated}`);
    console.log(`Avg Response Time: ${summary.avgResponseTime}ms`);
    console.log(`p95 Response Time: ${summary.p95ResponseTime}ms`);
    console.log(`p99 Response Time: ${summary.p99ResponseTime}ms`);
    console.log(`Error Rate:        ${summary.errorRate.toFixed(2)}%`);
    console.log('==========================================\n');

    return {
        'stdout': JSON.stringify(summary, null, 2) + '\n',
        'results/ticket-creation-results.json': JSON.stringify(summary, null, 2),
    };
}
