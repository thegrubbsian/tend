# Build the durable local model container

Provide the production and test container configurations and prove that saved
history survives reopening.

## Approach

- Add a small `TendModelContainer` factory over `ModelContainer`,
  `TendSchemaV1`, and `TendMigrationPlan`; do not add a generic repository.
- Build the production configuration as a file-backed local store with
  `cloudKitDatabase: .none`, so future entitlements cannot silently enable sync.
- Accept explicit in-memory and file-URL configurations for isolated tests.
- Keep container construction and save failures as thrown errors. Never fall
  back from a failed durable store to an in-memory store.
- Save test data explicitly through `ModelContext`, release the context and
  container, reopen the same URL, and refetch the complete aggregate.
- Add an executable schema audit for Apple's CloudKit compatibility constraints
  without requiring an iCloud account, entitlement, network, or live container.

## Surfaces

- `Sources/TendCore/Persistence/TendModelContainer.swift`
- `Tests/TendCoreTests/Persistence/PersistenceContainerTests.swift`
- `Tests/TendCoreTests/Persistence/CloudKitSchemaCompatibilityTests.swift`

## Tests

- Verify production configuration disables CloudKit and uses version one.
- Verify independent in-memory containers do not share state.
- Reopen a temporary file-backed store and compare habit, activity, bucket,
  snapshot, and entry values with what was explicitly saved.
- Prove an invalid store location reports an error without creating a volatile
  fallback.
- Audit schema metadata to prove there are no unique constraints or deny rules,
  every relationship is optional with an explicit inverse, and every
  nonoptional attribute has a schema-visible default.

## Edge cases

- Use a unique temporary directory per test and remove it only after every
  container referencing the store has been released.
- Keep tests deterministic and independent of the default Application Support
  location, wall-clock time, iCloud identity, and network availability.
- Treat a successful `ModelContext.save()` as the durability boundary; unsaved
  context mutations are not promised to survive termination.
