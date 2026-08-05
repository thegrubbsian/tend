import Foundation
import SwiftData

enum HabitRelationshipValidationError: Error, Equatable {
  case invalidBucketRelationship(String)
  case invalidEntryRelationship(UUID)
}

@MainActor
struct HabitRelationshipValidator {
  let context: ModelContext

  func validateGraph(for habit: Habit) throws {
    let habitIdentifier = habit.persistentModelID
    let bucketDescriptor = FetchDescriptor<HabitBucket>(
      predicate: #Predicate<HabitBucket> { bucket in
        bucket.habit?.persistentModelID == habitIdentifier
      })
    var buckets = try context.fetch(bucketDescriptor)
    var bucketIdentifiers = Set(buckets.map(\.persistentModelID))
    for bucket in habit.buckets ?? []
    where bucketIdentifiers.insert(bucket.persistentModelID).inserted {
      buckets.append(bucket)
    }
    buckets.sort { first, second in
      if first.periodKey != second.periodKey {
        return first.periodKey < second.periodKey
      }
      return uuidPrecedes(first.id, second.id)
    }
    for bucket in buckets {
      guard isPersisted(bucket),
        bucket.habit?.persistentModelID == habitIdentifier
      else {
        throw HabitRelationshipValidationError.invalidBucketRelationship(bucket.periodKey)
      }
    }

    let entryDescriptor = FetchDescriptor<LogEntry>(
      predicate: #Predicate<LogEntry> { entry in
        entry.habit?.persistentModelID == habitIdentifier
      })
    var entries = try context.fetch(entryDescriptor)
    var entryIdentifiers = Set(entries.map(\.persistentModelID))
    for entry in habit.entries ?? []
    where entryIdentifiers.insert(entry.persistentModelID).inserted {
      entries.append(entry)
    }
    for bucket in buckets {
      for entry in bucket.entries ?? []
      where entryIdentifiers.insert(entry.persistentModelID).inserted {
        entries.append(entry)
      }
    }
    entries.sort { uuidPrecedes($0.id, $1.id) }
    for entry in entries {
      try validate(
        entry,
        habitIdentifier: habitIdentifier,
        bucketIdentifiers: bucketIdentifiers
      )
    }
  }

  func validate(_ bucket: HabitBucket, for habit: Habit) throws {
    let habitIdentifier = habit.persistentModelID
    guard isPersisted(bucket),
      bucket.habit?.persistentModelID == habitIdentifier
    else {
      throw HabitRelationshipValidationError.invalidBucketRelationship(bucket.periodKey)
    }
    let bucketIdentifiers: Set<PersistentIdentifier> = [bucket.persistentModelID]
    for entry in (bucket.entries ?? []).sorted(by: { uuidPrecedes($0.id, $1.id) }) {
      try validate(
        entry,
        habitIdentifier: habitIdentifier,
        bucketIdentifiers: bucketIdentifiers
      )
    }
  }

  func isPersisted<T>(_ model: T) -> Bool where T: PersistentModel {
    model.modelContext == context && model.persistentModelID.storeIdentifier != nil
      && !model.isDeleted
  }

  private func validate(
    _ entry: LogEntry,
    habitIdentifier: PersistentIdentifier,
    bucketIdentifiers: Set<PersistentIdentifier>
  ) throws {
    guard isPersisted(entry),
      entry.habit?.persistentModelID == habitIdentifier,
      let bucket = entry.bucket,
      isPersisted(bucket),
      bucket.habit?.persistentModelID == habitIdentifier,
      bucketIdentifiers.contains(bucket.persistentModelID),
      bucket.entries?.contains(where: {
        $0.persistentModelID == entry.persistentModelID
      }) == true
    else {
      throw HabitRelationshipValidationError.invalidEntryRelationship(entry.id)
    }
  }

  private func uuidPrecedes(_ first: UUID, _ second: UUID) -> Bool {
    var firstBytes = first.uuid
    var secondBytes = second.uuid
    return withUnsafeBytes(of: &firstBytes) { firstBuffer in
      withUnsafeBytes(of: &secondBytes) { secondBuffer in
        firstBuffer.lexicographicallyPrecedes(secondBuffer)
      }
    }
  }
}
