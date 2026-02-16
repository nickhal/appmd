import Foundation
import SwiftUI
import GRDB
import Combine

// MARK: - @Query Property Wrapper

/// A SwiftUI property wrapper that observes an AppMD query and automatically
/// updates the view when matching documents change on disk.
///
/// ```swift
/// struct CardListView: View {
///     @Query(sort: "position") var cards: [Card]
///     // or with filters:
///     @Query(
///         filter: ("column", "[[columns/todo]]"),
///         sort: "position"
///     ) var todoCards: [Card]
///
///     var body: some View {
///         ForEach(cards) { card in
///             Text(card.title)
///         }
///     }
/// }
/// ```
///
/// Requires an `AppMDStore` in the SwiftUI environment.
@propertyWrapper
public struct Query<T: AppMDModel>: DynamicProperty {

    @Environment(\.appMDStore) private var store

    @StateObject private var observer = QueryObserver<T>()

    private let buildQuery: () -> TypedQuery<T>

    public var wrappedValue: [T] {
        observer.results
    }

    /// Access the query observer for additional state (loading, error).
    public var projectedValue: QueryObserver<T> {
        observer
    }

    // MARK: - Initializers

    /// Query all items of this type.
    public init(
        sort: String? = nil,
        descending: Bool = false
    ) {
        let sortCol = sort
        let desc = descending
        self.buildQuery = {
            var q = TypedQuery<T>()
            if let col = sortCol {
                q = q.sort(by: col, descending: desc)
            }
            return q
        }
    }

    /// Query with a single filter condition.
    public init(
        filter: (String, DatabaseValueConvertible),
        sort: String? = nil,
        descending: Bool = false
    ) {
        let f = filter
        let sortCol = sort
        let desc = descending
        self.buildQuery = {
            var q = TypedQuery<T>().where(f.0, equals: f.1)
            if let col = sortCol {
                q = q.sort(by: col, descending: desc)
            }
            return q
        }
    }

    /// Query with multiple filter conditions.
    public init(
        filters: [(String, DatabaseValueConvertible)],
        sort: String? = nil,
        descending: Bool = false
    ) {
        let fs = filters
        let sortCol = sort
        let desc = descending
        self.buildQuery = {
            var q = TypedQuery<T>()
            for f in fs {
                q = q.where(f.0, equals: f.1)
            }
            if let col = sortCol {
                q = q.sort(by: col, descending: desc)
            }
            return q
        }
    }

    /// Query with a pre-built TypedQuery for full control.
    public init(query: @escaping @autoclosure () -> TypedQuery<T>) {
        self.buildQuery = query
    }

    // MARK: - DynamicProperty

    public mutating func update() {
        observer.bind(store: store, query: buildQuery())
    }
}

// MARK: - QueryObserver

/// Observable object that manages a GRDB ValueObservation for a typed query.
/// Used internally by `@Query` but also accessible via `$query` projected value.
public final class QueryObserver<T: AppMDModel>: ObservableObject {

    @Published public private(set) var results: [T] = []
    @Published public private(set) var error: Error?
    @Published public private(set) var isLoading: Bool = true

    private var cancellable: AnyDatabaseCancellable?
    private var boundQuery: String?
    private var boundStoreId: ObjectIdentifier?

    func bind(store: AppMDStore?, query: TypedQuery<T>) {
        guard let store else { return }

        // Avoid re-binding if same store + query
        let queryId = "\(query.buildSQL())"
        let storeId = ObjectIdentifier(store)
        if queryId == boundQuery && storeId == boundStoreId {
            return
        }
        boundQuery = queryId
        boundStoreId = storeId

        // Cancel previous observation
        cancellable?.cancel()

        let observation = query.observation()
        cancellable = observation.start(
            in: store.database,
            onError: { [weak self] err in
                DispatchQueue.main.async {
                    self?.error = err
                    self?.isLoading = false
                }
            },
            onChange: { [weak self] (newResults: [T]) in
                DispatchQueue.main.async {
                    self?.results = newResults
                    self?.error = nil
                    self?.isLoading = false
                }
            }
        )
    }

    deinit {
        cancellable?.cancel()
    }
}

// MARK: - Environment Key

/// Environment key for providing an `AppMDStore` to SwiftUI views.
///
/// Set it at the top of your view hierarchy:
/// ```swift
/// ContentView()
///     .environment(\.appMDStore, store)
/// ```
private struct AppMDStoreKey: EnvironmentKey {
    static let defaultValue: AppMDStore? = nil
}

public extension EnvironmentValues {
    var appMDStore: AppMDStore? {
        get { self[AppMDStoreKey.self] }
        set { self[AppMDStoreKey.self] = newValue }
    }
}
