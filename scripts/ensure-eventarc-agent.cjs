'use strict';
// Check or restore only the standard Eventarc managed service-agent role.
// Retains every other IAM binding and uses the policy etag for concurrency.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const auth = require(path.join(cli, 'auth'));
const { requireAuth } = require(path.join(cli, 'requireAuth'));
const { Client } = require(path.join(cli, 'apiv2'));
const project = 'edupro-8c4fd';
const member = 'serviceAccount:service-876132148030@gcp-sa-eventarc.iam.gserviceaccount.com';
const role = 'roles/eventarc.serviceAgent';
const options = { skipLog: { body: true, resBody: true, queryParams: true }, timeout: 30000 };
async function main() {
  await requireAuth({ project, ...auth.getProjectDefaultAccount(process.cwd()) });
  const api = new Client({ urlPrefix: 'https://cloudresourcemanager.googleapis.com' });
  const policy = (await api.post(`/v1/projects/${project}:getIamPolicy`, { options: { requestedPolicyVersion: 3 } }, options)).body;
  const present = (policy.bindings || []).some((binding) => binding.role === role && !binding.condition && binding.members?.includes(member));
  if (present || !process.argv.includes('--apply')) {
    console.log(JSON.stringify({ project, eventarcServiceAgentRolePresent: present, changed: false }));
    return;
  }
  if (!policy.etag) throw new Error('Missing IAM concurrency token');
  const binding = (policy.bindings || []).find((binding) => binding.role === role && !binding.condition);
  if (binding) binding.members.push(member);
  else policy.bindings = [...(policy.bindings || []), { role, members: [member] }];
  await api.post(`/v1/projects/${project}:setIamPolicy`, { policy }, options);
  console.log(JSON.stringify({ project, eventarcServiceAgentRolePresent: true, changed: true }));
}
main().catch(() => { console.error('Eventarc role verification failed. No IAM identities or credentials logged.'); process.exitCode = 1; });
