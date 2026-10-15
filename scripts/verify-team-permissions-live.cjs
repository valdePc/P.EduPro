'use strict';

// No credentials or school identifiers. Verify the deployed functions reject
// unauthenticated requests before touching any school data.
async function main() {
  const endpoints = [
    'getTeamAccess', 'listTeamSchools', 'getTeamSchoolSummary', 'getTeamSchoolBilling',
    'updateSchoolPlanLimits', 'updateSchoolLocation', 'unlockSchoolAccessIp', 'searchSchoolPlaces', 'createSchool',
  ];
  for (const name of endpoints) {
    const response = await fetch(`https://us-central1-edupro-8c4fd.cloudfunctions.net/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: {} }), signal: AbortSignal.timeout(30000),
    });
    console.log(`${name}: HTTP ${response.status}`);
    if (![401, 403].includes(response.status)) {
      throw new Error(`Unexpected authorization response from ${name}`);
    }
    await response.body?.cancel();
  }
}
main().catch(() => { console.error('Live authorization check did not pass.'); process.exitCode = 1; });
