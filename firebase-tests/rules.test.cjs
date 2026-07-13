const fs = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');
const { ref: databaseRef, get, set } = require('firebase/database');
const { ref: storageRef, getBytes, uploadString } = require('firebase/storage');

const projectId = 'agriculture-pest-system-96401';
const root = path.resolve(__dirname, '..');
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8')},
    database: {rules: fs.readFileSync(path.join(root, 'database.rules.json'), 'utf8')},
    storage: {rules: fs.readFileSync(path.join(root, 'storage.rules'), 'utf8')},
  });
});

after(async () => environment?.cleanup());
beforeEach(async () => environment.clearFirestore());

describe('Firestore rules', () => {
  it('deny unauthenticated reads and cross-user access', async () => {
    const owner = environment.authenticatedContext('farmer-a').firestore();
    const stranger = environment.authenticatedContext('farmer-b').firestore();
    await assertSucceeds(setDoc(doc(owner, 'farms/farm-1'), {ownerId: 'farmer-a'}));
    await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'farms/farm-1')));
    await assertFails(getDoc(doc(stranger, 'farms/farm-1')));
  });

  it('allow owners and privileged roles while protecting AI models', async () => {
    const owner = environment.authenticatedContext('farmer-a').firestore();
    const admin = environment.authenticatedContext('admin-a', {role: 'admin'}).firestore();
    await assertSucceeds(setDoc(doc(owner, 'detections/detection-1'), {userId: 'farmer-a'}));
    await assertSucceeds(getDoc(doc(owner, 'detections/detection-1')));
    await assertFails(setDoc(doc(owner, 'ai_models/model-1'), {userId: 'farmer-a'}));
    await assertSucceeds(setDoc(doc(admin, 'ai_models/model-1'), {version: '1'}));
  });

  const privilegedRoles = [
    'admin',
    'administrator',
    'agricultural_officer',
    'laboratory_staff',
  ];
  for (const role of privilegedRoles) {
    it(`allow ${role} to read operational records`, async () => {
      await environment.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), 'farms/protected-farm'), {ownerId: 'farmer-a'});
      });
      const actor = environment.authenticatedContext(`${role}-user`, {role}).firestore();
      await assertSucceeds(getDoc(doc(actor, 'farms/protected-farm')));
    });
  }

  for (const role of ['farmer', 'researcher', 'extension_worker']) {
    it(`deny ${role} access to another farmer's private record`, async () => {
      await environment.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), 'farms/protected-farm'), {ownerId: 'farmer-a'});
      });
      const actor = environment.authenticatedContext(`${role}-user`, {role}).firestore();
      await assertFails(getDoc(doc(actor, 'farms/protected-farm')));
    });
  }

  it('allow every signed-in role to read published AI model metadata', async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'ai_models/model-public'), {version: '1'});
    });
    const roles = [...privilegedRoles, 'farmer', 'researcher', 'extension_worker'];
    for (const role of roles) {
      const actor = environment.authenticatedContext(`${role}-reader`, {role}).firestore();
      await assertSucceeds(getDoc(doc(actor, 'ai_models/model-public')));
    }
  });
});

describe('Realtime Database rules', () => {
  it('restrict IoT readings to the owner or privileged role', async () => {
    const owner = environment.authenticatedContext('farmer-a').database();
    const stranger = environment.authenticatedContext('farmer-b').database();
    const reading = databaseRef(owner, 'iot_readings/farmer-a/device-1');
    await assertSucceeds(set(reading, {timestamp: Date.now(), moisture: 42}));
    await assertSucceeds(get(reading));
    await assertFails(get(databaseRef(stranger, 'iot_readings/farmer-a/device-1')));
  });
});

describe('Storage rules', () => {
  it('accept owner images and reject cross-user or invalid uploads', async () => {
    const owner = environment.authenticatedContext('farmer-a').storage();
    const stranger = environment.authenticatedContext('farmer-b').storage();
    const image = storageRef(owner, 'detections/farmer-a/leaf.jpg');
    await assertSucceeds(uploadString(image, 'image-data', 'raw', {contentType: 'image/jpeg'}));
    await assertSucceeds(getBytes(image));
    await assertFails(getBytes(storageRef(stranger, 'detections/farmer-a/leaf.jpg')));
    await assertFails(uploadString(storageRef(owner, 'detections/farmer-a/code.exe'), 'x', 'raw', {contentType: 'application/octet-stream'}));
  });
});
