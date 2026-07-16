const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase/app');
const {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signOut,
} = require('firebase/auth');

describe('Firebase Auth emulator', () => {
  let app;
  let auth;

  before(() => {
    app = initializeApp({apiKey: 'demo-key', projectId: 'agriculture-pest-system-96401'}, `auth-${Date.now()}`);
    auth = getAuth(app);
    connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
  });

  after(async () => deleteApp(app));

  it('creates, signs out, signs in, and accepts reset requests', async () => {
    const email = `farmer-${Date.now()}@example.test`;
    const password = 'StrongPassword1!';
    const created = await createUserWithEmailAndPassword(auth, email, password);
    assert.equal(created.user.email, email);
    await signOut(auth);
    const signedIn = await signInWithEmailAndPassword(auth, email, password);
    assert.equal(signedIn.user.uid, created.user.uid);
    await sendPasswordResetEmail(auth, email);
  });

  it('rejects invalid credentials', async () => {
    await assert.rejects(
      signInWithEmailAndPassword(auth, 'missing@example.test', 'WrongPassword1!'),
    );
  });
});

