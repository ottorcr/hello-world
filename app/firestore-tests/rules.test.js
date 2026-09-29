// Security rules tests. Run with `npm test` (starts the Firestore emulator).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Bytes,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-random-thoughts',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const db = (uid, { verified = true } = {}) =>
  env.authenticatedContext(uid, { email_verified: verified }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

async function request(from, to, name = from) {
  await setDoc(doc(db(from), `users/${to}/requests/${from}`), {
    displayName: name,
    createdAt: serverTimestamp(),
  });
}

/** `acceptor` accepts the pending request from `requester`. */
function acceptBatch(acceptor, requester) {
  const d = db(acceptor);
  const b = writeBatch(d);
  b.set(doc(d, `users/${acceptor}/friends/${requester}`), {
    displayName: requester,
    since: serverTimestamp(),
  });
  b.set(doc(d, `users/${requester}/friends/${acceptor}`), {
    displayName: acceptor,
    since: serverTimestamp(),
  });
  b.delete(doc(d, `users/${acceptor}/requests/${requester}`));
  return b.commit();
}

async function befriend(a, b) {
  await request(a, b);
  await acceptBatch(b, a);
}

const post = (author, extra = {}) => ({
  authorId: author,
  authorName: author,
  text: 'hello',
  hasImage: false,
  createdAt: serverTimestamp(),
  ...extra,
});

describe('friend requests', () => {
  test('verified user can send a request', async () => {
    await assertSucceeds(request('alice', 'bob'));
  });

  test('unverified email cannot send a request', async () => {
    await assertFails(
      setDoc(doc(db('alice', { verified: false }), 'users/bob/requests/alice'), {
        displayName: 'alice',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('cannot send a request pretending to be someone else', async () => {
    await assertFails(
      setDoc(doc(db('mallory'), 'users/bob/requests/alice'), {
        displayName: 'alice',
        createdAt: serverTimestamp(),
      }),
    );
  });

  test('cannot befriend yourself', async () => {
    await assertFails(request('alice', 'alice'));
  });

  test('blocked user cannot send a request', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/bob/blocked/mallory'), { createdAt: new Date() }),
    );
    await assertFails(request('mallory', 'bob'));
  });

  test('only the recipient can see incoming requests', async () => {
    await request('alice', 'bob');
    await assertSucceeds(getDocs(collection(db('bob'), 'users/bob/requests')));
    await assertFails(getDocs(collection(db('mallory'), 'users/bob/requests')));
  });
});

describe('friendships', () => {
  test('accepting a pending request creates both sides', async () => {
    await request('alice', 'bob');
    await assertSucceeds(acceptBatch('bob', 'alice'));
  });

  test('cannot add a friend without their request', async () => {
    await assertFails(acceptBatch('mallory', 'bob'));
  });

  test('requester cannot approve their own request', async () => {
    await request('mallory', 'bob');
    // Mallory tries to write both sides herself.
    await assertFails(acceptBatch('mallory', 'bob'));
  });

  test('friend list is private', async () => {
    await befriend('alice', 'bob');
    await assertSucceeds(getDocs(collection(db('bob'), 'users/bob/friends')));
    await assertFails(getDocs(collection(db('alice'), 'users/bob/friends')));
  });

  test('either side can unfriend', async () => {
    await befriend('alice', 'bob');
    await assertSucceeds(deleteDoc(doc(db('alice'), 'users/bob/friends/alice')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'users/alice/friends/bob')));
  });
});

describe('inbox', () => {
  test('friend can send to your inbox and you can read it', async () => {
    await befriend('alice', 'bob');
    await assertSucceeds(setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('alice')));
    await assertSucceeds(getDocs(collection(db('bob'), 'users/bob/inbox')));
  });

  test('non-friend cannot send to your inbox', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'users/bob/inbox/p1'), post('mallory')));
  });

  test('cannot send as someone else', async () => {
    await befriend('alice', 'bob');
    await assertFails(setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('carol')));
  });

  test('cannot post into your own inbox', async () => {
    await assertFails(setDoc(doc(db('bob'), 'users/bob/inbox/p1'), post('bob')));
  });

  test('after unfriending, they cannot send anymore', async () => {
    await befriend('alice', 'bob');
    await deleteDoc(doc(db('bob'), 'users/bob/friends/alice'));
    await assertFails(setDoc(doc(db('alice'), 'users/bob/inbox/p2'), post('alice')));
  });

  test('others cannot read your inbox', async () => {
    await befriend('alice', 'bob');
    await setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('alice'));
    await assertFails(getDocs(collection(db('mallory'), 'users/bob/inbox')));
    await assertFails(getDoc(doc(db('mallory'), 'users/bob/inbox/p1')));
    await assertFails(getDocs(collection(anon(), 'users/bob/inbox')));
  });

  test('author can find and unsend only their own copies', async () => {
    await befriend('alice', 'bob');
    await befriend('carol', 'bob');
    await setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('alice'));
    await setDoc(doc(db('carol'), 'users/bob/inbox/p2'), post('carol'));
    await assertSucceeds(
      getDocs(query(collection(db('alice'), 'users/bob/inbox'), where('authorId', '==', 'alice'))),
    );
    await assertFails(deleteDoc(doc(db('alice'), 'users/bob/inbox/p2')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'users/bob/inbox/p1')));
  });

  test('text is limited to 280 characters', async () => {
    await befriend('alice', 'bob');
    await assertFails(
      setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('alice', { text: 'x'.repeat(281) })),
    );
  });

  test('extra fields are rejected', async () => {
    await befriend('alice', 'bob');
    await assertFails(
      setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('alice', { link: 'https://evil' })),
    );
  });
});

describe('images', () => {
  const image = (author) => ({
    authorId: author,
    data: Bytes.fromUint8Array(new Uint8Array([0xff, 0xd8, 0xff])),
    createdAt: serverTimestamp(),
  });

  test('only friends who received the post can see the photo', async () => {
    await befriend('alice', 'bob');
    await setDoc(doc(db('alice'), 'images/p1'), image('alice'));
    await setDoc(doc(db('alice'), 'users/bob/inbox/p1'), post('alice', { hasImage: true }));
    await assertSucceeds(getDoc(doc(db('alice'), 'images/p1')));
    await assertSucceeds(getDoc(doc(db('bob'), 'images/p1')));
    await assertFails(getDoc(doc(db('mallory'), 'images/p1')));
  });

  test('a fake inbox entry from an accomplice does not unlock the photo', async () => {
    await befriend('alice', 'bob');
    await befriend('carol', 'mallory');
    await setDoc(doc(db('alice'), 'images/p1'), image('alice'));
    // Carol drops a post with the same id into Mallory's inbox.
    await setDoc(doc(db('carol'), 'users/mallory/inbox/p1'), post('carol', { hasImage: true }));
    await assertFails(getDoc(doc(db('mallory'), 'images/p1')));
  });

  test('images cannot be listed', async () => {
    await setDoc(doc(db('alice'), 'images/p1'), image('alice'));
    await assertFails(getDocs(collection(db('bob'), 'images')));
  });

  test('cannot upload an image as someone else', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'images/p1'), image('alice')));
  });

  test('images over the size limit are rejected', async () => {
    await assertFails(
      setDoc(doc(db('alice'), 'images/p1'), {
        ...image('alice'),
        data: Bytes.fromUint8Array(new Uint8Array(901 * 1024)),
      }),
    );
  });
});

describe('friend codes and profiles', () => {
  test('codes can be looked up one at a time but not listed', async () => {
    await assertSucceeds(
      setDoc(doc(db('alice'), 'friendCodes/ABCD2345'), { uid: 'alice', displayName: 'Alice' }),
    );
    await assertSucceeds(getDoc(doc(db('bob'), 'friendCodes/ABCD2345')));
    await assertFails(getDocs(collection(db('bob'), 'friendCodes')));
  });

  test('cannot claim a code for someone else', async () => {
    await assertFails(
      setDoc(doc(db('mallory'), 'friendCodes/ABCD2345'), { uid: 'alice', displayName: 'Alice' }),
    );
  });

  test('cannot take over an existing code', async () => {
    await setDoc(doc(db('alice'), 'friendCodes/ABCD2345'), { uid: 'alice', displayName: 'Alice' });
    await assertFails(
      setDoc(doc(db('mallory'), 'friendCodes/ABCD2345'), { uid: 'mallory', displayName: 'M' }),
    );
  });

  test('profiles are private', async () => {
    const d = db('alice');
    const b = writeBatch(d);
    b.set(doc(d, 'friendCodes/ABCD2345'), { uid: 'alice', displayName: 'Alice' });
    b.set(doc(d, 'users/alice'), {
      displayName: 'Alice',
      friendCode: 'ABCD2345',
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(b.commit());
    await assertFails(getDoc(doc(db('bob'), 'users/alice')));
  });
});

describe('reports', () => {
  test('can file a report but nobody can read reports from the app', async () => {
    await assertSucceeds(
      setDoc(doc(db('bob'), 'reports/r1'), {
        reporterId: 'bob',
        reportedUid: 'mallory',
        postId: 'p1',
        text: 'mean thing',
        reason: 'harassment',
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(getDoc(doc(db('bob'), 'reports/r1')));
  });
});

describe('account deletion', () => {
  test('a user can remove everything they created, everywhere', async () => {
    await befriend('alice', 'bob');
    await request('alice', 'carol');
    const a = db('alice');
    await setDoc(doc(a, 'users/alice/outgoing/carol'), { createdAt: serverTimestamp() });
    await setDoc(doc(a, 'images/p1'), {
      authorId: 'alice',
      data: Bytes.fromUint8Array(new Uint8Array([1])),
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(a, 'users/alice/sent/p1'), {
      text: 'hi',
      hasImage: true,
      recipients: ['bob'],
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(a, 'users/bob/inbox/p1'), post('alice', { hasImage: true }));
    await setDoc(doc(db('bob'), 'users/alice/inbox/p9'), post('bob'));

    const b = writeBatch(a);
    for (const path of [
      'users/bob/inbox/p1',
      'images/p1',
      'users/alice/sent/p1',
      'users/alice/friends/bob',
      'users/bob/friends/alice',
      'users/carol/requests/alice',
      'users/alice/outgoing/carol',
      'users/alice/inbox/p9',
      'users/alice',
    ]) {
      b.delete(doc(a, path));
    }
    await assertSucceeds(b.commit());
    await assertFails(getDoc(doc(db('bob'), 'images/p1')));
  });

  test('cannot delete other people’s data', async () => {
    await befriend('bob', 'carol');
    await setDoc(doc(db('bob'), 'users/carol/inbox/p1'), post('bob'));
    await assertFails(deleteDoc(doc(db('mallory'), 'users/carol/inbox/p1')));
    await assertFails(deleteDoc(doc(db('mallory'), 'users/carol/friends/bob')));
    await assertFails(deleteDoc(doc(db('mallory'), 'users/carol')));
  });
});
