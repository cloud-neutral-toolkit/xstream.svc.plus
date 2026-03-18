// AUTO-GENERATED FFI BINDINGS
import 'dart:ffi' as ffi;

typedef StartNodeServiceNative =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef StartNodeServiceDart =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);

typedef CreateWindowsServiceNative =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
    );
typedef CreateWindowsServiceDart =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
    );

typedef StopNodeServiceNative =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef StopNodeServiceDart =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);

typedef WriteConfigFilesNative =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
    );
typedef WriteConfigFilesDart =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
    );

typedef CheckNodeStatusNative = ffi.Int32 Function(ffi.Pointer<ffi.Char>);
typedef CheckNodeStatusDart = int Function(ffi.Pointer<ffi.Char>);

typedef PerformActionNative =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
    );
typedef PerformActionDart =
    ffi.Pointer<ffi.Char> Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
    );

typedef FreeCStringNative = ffi.Void Function(ffi.Pointer<ffi.Char>);
typedef FreeCStringDart = void Function(ffi.Pointer<ffi.Char>);
typedef IsXrayDownloadingNative = ffi.Int32 Function();
typedef IsXrayDownloadingDart = int Function();
typedef StartXrayNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef StartXrayDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef StopXrayNative = ffi.Pointer<ffi.Char> Function();
typedef StopXrayDart = ffi.Pointer<ffi.Char> Function();
typedef DesktopIntegrationCommandNative =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef DesktopIntegrationCommandDart =
    ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef InitTrayNative = ffi.Void Function();
typedef InitTrayDart = void Function();
typedef GetDesktopRuntimeSnapshotNative = ffi.Pointer<ffi.Char> Function();
typedef GetDesktopRuntimeSnapshotDart = ffi.Pointer<ffi.Char> Function();

GetDesktopRuntimeSnapshotDart? _lookupGetDesktopRuntimeSnapshot(
  ffi.DynamicLibrary lib,
) {
  try {
    return lib.lookupFunction<
      GetDesktopRuntimeSnapshotNative,
      GetDesktopRuntimeSnapshotDart
    >('GetDesktopRuntimeSnapshot');
  } catch (_) {
    return null;
  }
}

class BridgeBindings {
  BridgeBindings(ffi.DynamicLibrary lib)
    : startNodeService = lib
          .lookupFunction<StartNodeServiceNative, StartNodeServiceDart>(
            'StartNodeService',
          ),
      createWindowsService = lib
          .lookupFunction<CreateWindowsServiceNative, CreateWindowsServiceDart>(
            'CreateWindowsService',
          ),
      stopNodeService = lib
          .lookupFunction<StopNodeServiceNative, StopNodeServiceDart>(
            'StopNodeService',
          ),
      writeConfigFiles = lib
          .lookupFunction<WriteConfigFilesNative, WriteConfigFilesDart>(
            'WriteConfigFiles',
          ),
      checkNodeStatus = lib
          .lookupFunction<CheckNodeStatusNative, CheckNodeStatusDart>(
            'CheckNodeStatus',
          ),
      performAction = lib
          .lookupFunction<PerformActionNative, PerformActionDart>(
            'PerformAction',
          ),
      freeCString = lib.lookupFunction<FreeCStringNative, FreeCStringDart>(
        'FreeCString',
      ),
      isXrayDownloading = lib
          .lookupFunction<IsXrayDownloadingNative, IsXrayDownloadingDart>(
            'IsXrayDownloading',
          ),
      startXray = lib.lookupFunction<StartXrayNative, StartXrayDart>(
        'StartXray',
      ),
      stopXray = lib.lookupFunction<StopXrayNative, StopXrayDart>('StopXray'),
      desktopIntegrationCommand = lib.lookupFunction<
        DesktopIntegrationCommandNative,
        DesktopIntegrationCommandDart
      >('DesktopIntegrationCommand'),
      initTray = lib.lookupFunction<InitTrayNative, InitTrayDart>('InitTray'),
      getDesktopRuntimeSnapshot = _lookupGetDesktopRuntimeSnapshot(lib);

  final StartNodeServiceDart startNodeService;
  final CreateWindowsServiceDart createWindowsService;
  final StopNodeServiceDart stopNodeService;
  final WriteConfigFilesDart writeConfigFiles;
  final CheckNodeStatusDart checkNodeStatus;
  final PerformActionDart performAction;
  final FreeCStringDart freeCString;
  final IsXrayDownloadingDart isXrayDownloading;
  final StartXrayDart startXray;
  final StopXrayDart stopXray;
  final DesktopIntegrationCommandDart desktopIntegrationCommand;
  final InitTrayDart initTray;
  final GetDesktopRuntimeSnapshotDart? getDesktopRuntimeSnapshot;
}
