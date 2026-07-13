import http from 'k6/http';
import {check} from 'k6';

const baseUrl = __ENV.BASE_URL;
const virtualUsers = Number.parseInt(__ENV.VIRTUAL_USERS || '20', 10);
const duration = __ENV.TEST_DURATION || '60s';

if (!baseUrl || !baseUrl.startsWith('https://')) {
  throw new Error('BASE_URL must be a staging HTTPS URL');
}

export const options = {
  vus: Math.min(Math.max(virtualUsers, 1), 100),
  duration,
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const response = http.get(baseUrl, {
    redirects: 3,
    tags: {scenario: 'public_shell_read'},
  });
  check(response, {
    'status is 200': (result) => result.status === 200,
    'Flutter shell returned': (result) =>
      result.body.includes('flutter_bootstrap.js') || result.body.includes('main.dart.js'),
  });
}
