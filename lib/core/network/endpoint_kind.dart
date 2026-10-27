/// Which address family an endpoint belongs to (contract §1.1).
///
/// Lives in `core` so that error types and models can reference it without
/// depending on the data layer.
enum EndpointKind { lan, wan }

/// Which endpoint the user prefers (contract §1.1).
enum EndpointPreference { auto, lan, wan }
