// Applies every collection definition + index to the target database.
// Idempotent: re-running collMods the validator and no-ops existing indexes.
//
//   mongosh "$MONGO_URI" --file mongo/init.js
//
// MONGO_DB defaults to `codementor`.

/* global db, load, print */

const targetDb = (typeof process !== "undefined" && process.env && process.env.MONGO_DB) || "codementor";
const database = db.getSiblingDB(targetDb);

const modules = [
  "mongo/schemas/01-exercise-contents.js",
  "mongo/schemas/02-lesson-contents.js",
  "mongo/schemas/03-submission-run-details.js",
  "mongo/schemas/04-article-contents.js",
  "mongo/schemas/05-notifications.js",
  "mongo/schemas/06-notification-reads.js",
];

print(`\n== codementor mongo init → ${targetDb} ==`);

for (const path of modules) {
  // Each schema file leaves `apply` in scope when loaded by mongosh.
  load(path);
  const name = apply(database); // eslint-disable-line no-undef
  const count = database.getCollection(name).getIndexes().length;
  print(`  ✓ ${name.padEnd(24)} validator applied, ${count} indexes`);
}

print(`\ncollections: ${database.getCollectionNames().join(", ")}\n`);
