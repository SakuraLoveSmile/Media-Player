/// A discovered DLNA/UPnP media renderer (S19).
class DlnaDevice {
  const DlnaDevice({
    required this.id,
    required this.name,
    required this.controlUrl,
    required this.address,
  });

  /// Stable identity (the SSDP USN, falling back to the description location)
  /// used to de-duplicate repeated search responses.
  final String id;

  /// Human-readable `friendlyName` from the device description.
  final String name;

  /// Absolute AVTransport control URL that SOAP actions are posted to.
  final String controlUrl;

  /// Host:port of the renderer, shown as a secondary label.
  final String address;
}
