// Separate, opt-in UAT entrypoint. The product main never imports this file.
// Authentication, secure storage, routing and the controllers under test are real.
// Only the three external completions are controlled; no provider is charged.
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main.dart' show RealEstateApp;
import 'core/local/stage6_secure_session_store.dart';
import 'core/network/api_client.dart';
import 'features/account/data/auth_controller.dart';
import 'features/account/data/auth_repository.dart';
import 'features/discovery/data/ai_repository.dart';
import 'features/discovery/data/marketplace_search_session.dart';
import 'features/discovery/data/smart_search_session.dart';
import 'features/discovery/domain/smart_search_filters.dart';
import 'features/properties/data/property_repository.dart';
import 'features/properties/domain/property_details.dart';
import 'features/properties/presentation/listing_editor_screen.dart';
import 'features/properties/presentation/personal_listing_creation_gate.dart';
import 'features/properties/presentation/property_location_picker_screen.dart';
import 'router/app_router.dart';

const callbackHarnessMarker = 'AQER_PHASE23_CALLBACK_HARNESS_V1';
const callbackApi = 'https://real-estate-uat-api-frankfurt.onrender.com/api';
const oldAiInput = 'P23 A controlled AI';
const oldResultsInput = 'P23 A controlled results';
const oldAiResult = 'P23 A stale reply must not apply';
const newDraftText = 'P23 B untouched search';
const editorTitleA = 'P23 A controlled location';
const editorTitleB = 'P23 B untouched location';

bool callbackHarnessAllowed({required bool enabled, required String environment, required String api}) =>
  enabled && environment == 'uat' && api == callbackApi;

void main() {
  if (!callbackHarnessAllowed(enabled: const bool.fromEnvironment('AQER_PHASE23_CALLBACK_HARNESS'),
      environment: ApiEnvironmentConfig.environment, api: ApiEnvironmentConfig.configuredBaseUrl)) {
    throw StateError('Explicit pinned UAT callback target required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final gate = CallbackGate();
  runApp(ProviderScope(overrides: [
    aiRepositoryProvider.overrideWith((ref) => CallbackAiRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider), gate)),
    propertyRepositoryProvider.overrideWith((ref) => CallbackPropertyRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider), gate)),
    propertyCurrentLocationProvider.overrideWithValue(gate.captureGps),
  ], child: CallbackApp(gate: gate)));
}

// Installed on the existing Dio before any product widget builds. Auth and
// ordinary API requests retain their normal transport, interceptors and TLS.
class NoPaidAi extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (RegExp(r'(^|/)ai(/|$)').hasMatch(options.uri.path) || RegExp(r'/properties/[0-9]+/ask$').hasMatch(options.uri.path)) {
      handler.reject(DioException(requestOptions: options, error: 'Controlled UAT target: external AI disabled'));
    } else { handler.next(options); }
  }
}

String callbackState(SmartSearchState s) => jsonEncode({
  'filters': s.filters.values, 'ids': s.rows.map((r) => r.id).toList(), 'revision': s.revision,
  'page': s.page, 'more': s.more, 'interpreting': s.interpreting, 'loading': s.loading,
  'started': s.started, 'message': s.message, 'lastRequest': s.lastRequest,
  'draftText': s.draftText, 'aiError': s.aiError, 'resultsError': s.resultsError,
});

class CallbackGate extends ChangeNotifier {
  late int? Function() actor;
  late SmartSearchSession Function() aiSession, resultsSession;
  int get epoch => Stage6SecureSessionStore.instance.sessionEpoch;
  int clock = 0, bLoginOrder = 0, errors = 0, forbiddenOldSearches = 0;
  int aiCapture = 0, aiEpoch = -1, aiRevision = 0, aiRelease = 0, aiComplete = 0;
  int resultsCapture = 0, resultsEpoch = -1, resultsRelease = 0, resultsComplete = 0;
  int gpsCapture = 0, gpsEpoch = -1, gpsRelease = 0, gpsComplete = 0;
  int bSeedOrder = 0, bEpoch = -1;
  String aiStatus = 'CB AI idle', resultsStatus = 'CB results idle', gpsStatus = 'CB GPS idle';
  String? bAi, bResults;
  Completer<Map<String, dynamic>>? aiReply;
  Completer<(List<PropertySummary>, bool)>? resultsReply;
  Completer<PropertyLocationSelection>? gpsReply;
  Future<void>? aiOperation, resultsOperation;
  CancelToken? oldResultsTransfer;
  GlobalKey? editorB;

  void changed() => notifyListeners();
  void recordActor(int? id) { if (id == 26) bLoginOrder = ++clock; changed(); }
  void _requireA() { if (actor() != 66 || bSeedOrder != 0) throw StateError('Pinned A required'); }
  void _requireB(int capturedEpoch) {
    if (actor() != 26 || bSeedOrder == 0 || epoch != bEpoch || epoch == capturedEpoch || bLoginOrder == 0) {
      throw StateError('Normal replacement B session and seed required');
    }
  }
  Future<Map<String, dynamic>> captureAi(int revision) {
    _requireA(); if (aiReply != null) throw StateError('AI already captured');
    aiEpoch = epoch; aiCapture = ++clock; aiRevision = revision;
    aiReply = Completer<Map<String, dynamic>>(); aiStatus = 'CB AI held'; changed(); return aiReply!.future;
  }
  Future<(List<PropertySummary>, bool)> captureResults(CancelToken? transfer) {
    _requireA(); if (resultsReply != null) throw StateError('Results already captured');
    resultsEpoch = epoch; resultsCapture = ++clock; oldResultsTransfer = transfer;
    resultsReply = Completer<(List<PropertySummary>, bool)>(); resultsStatus = 'CB results held'; changed();
    // Deliberately ignore cancellation, as a decoder may already have finished.
    return resultsReply!.future;
  }
  Future<PropertyLocationSelection> captureGps() async {
    _requireA(); if (gpsReply != null) throw StateError('GPS already captured');
    gpsEpoch = epoch; gpsCapture = ++clock; gpsReply = Completer<PropertyLocationSelection>();
    gpsStatus = 'CB GPS held'; changed();
    final point = await gpsReply!.future; gpsComplete = ++clock; changed(); return point;
  }
  void startAi() {
    _requireA(); aiOperation = aiSession().interpret(oldAiInput); changed();
  }
  void startResults() {
    _requireA(); resultsOperation = resultsSession().replaceManually(SmartSearchFilters.fromMap({'search': oldResultsInput})); changed();
  }
  void seedB() {
    if (actor() != 26 || bSeedOrder != 0 || bLoginOrder == 0 || aiReply == null || resultsReply == null || gpsReply == null) {
      throw StateError('All A callbacks must be held before B seed');
    }
    aiSession().setDraftText(newDraftText); resultsSession().setDraftText(newDraftText);
    bEpoch = epoch; bAi = callbackState(aiSession().snapshot); bResults = callbackState(resultsSession().snapshot);
    bSeedOrder = ++clock; changed();
  }
  bool bUnchanged() => actor() == 26 && epoch == bEpoch && bAi == callbackState(aiSession().snapshot) &&
    bResults == callbackState(resultsSession().snapshot) && forbiddenOldSearches == 0 && errors == 0;
  Future<void> releaseAi() async {
    _requireB(aiEpoch); if (aiReply == null || aiReply!.isCompleted) throw StateError('AI not held');
    aiRelease = ++clock; aiReply!.complete({'revision': aiRevision, 'filters': {'search': oldAiResult, 'type': 'apartment'}, 'message': oldAiResult});
    await aiOperation; aiComplete = ++clock; aiStatus = bUnchanged() ? 'CB AI PASS' : 'CB AI FAIL'; changed();
  }
  Future<void> releaseResults() async {
    _requireB(resultsEpoch); if (resultsReply == null || resultsReply!.isCompleted) throw StateError('Results not held');
    resultsRelease = ++clock; resultsReply!.complete((<PropertySummary>[], true));
    await resultsOperation; resultsComplete = ++clock;
    resultsStatus = bUnchanged() && oldResultsTransfer?.isCancelled == true ? 'CB results PASS' : 'CB results FAIL'; changed();
  }
  bool bEditorEmpty() {
    var empty = false, preview = false;
    void visit(Element e) {
      final w = e.widget;
      if (w is Text && w.data == 'حدد نقطة العقار أولًا') empty = true;
      if (w.key == const ValueKey('listing-location-preview')) preview = true;
      e.visitChildElements(visit);
    }
    final element = editorB?.currentContext;
    final editor = element?.widget;
    if (editor is! ListingEditorScreen || (editor.localRecovery?['fields'] as Map?)?['title'] != editorTitleB) return false;
    if (element is Element) visit(element);
    return empty && !preview;
  }
  Future<void> releaseGps() async {
    _requireB(gpsEpoch);
    if (gpsReply == null || gpsReply!.isCompleted || !bEditorEmpty()) throw StateError('Actual B editor must be empty first');
    gpsRelease = ++clock; gpsReply!.complete(const PropertyLocationSelection(latitude: 15.3694, longitude: 44.1910, method: 'gps'));
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;
    gpsStatus = bUnchanged() && bEditorEmpty() && gpsComplete > gpsRelease ? 'CB GPS PASS' : 'CB GPS FAIL'; changed();
  }
  Map<String, int> get metadata => {
    'v':1, 'actor': actor() == 66 ? 1 : actor() == 26 ? 2 : 0, 'bLogin': bLoginOrder,
    'bSeed': bSeedOrder, 'bEpoch': bEpoch, 'aiCapture': aiCapture, 'aiEpoch': aiEpoch,
    'aiRelease': aiRelease, 'aiComplete': aiComplete, 'resultsCapture': resultsCapture,
    'resultsEpoch': resultsEpoch, 'resultsRelease': resultsRelease, 'resultsComplete': resultsComplete,
    'gpsCapture': gpsCapture, 'gpsEpoch': gpsEpoch, 'gpsRelease': gpsRelease, 'gpsComplete': gpsComplete,
    'cancelled': oldResultsTransfer?.isCancelled == true ? 1 : 0, 'errors': errors, 'forbidden': forbiddenOldSearches,
  };
}

class CallbackAiRepository extends AiRepository {
  CallbackAiRepository(Dio dio, AuthRepository auth, this.gate) : super(dio, auth);
  final CallbackGate gate;
  @override
  Future<Map<String, dynamic>> refine(String message, Map<String, dynamic> filters, int revision) {
    if (message != oldAiInput) throw StateError('Only controlled AI input permitted');
    return gate.captureAi(revision);
  }
}
class CallbackPropertyRepository extends PropertyRepository {
  CallbackPropertyRepository(Dio dio, AuthRepository auth, this.gate) : super(dio, auth);
  final CallbackGate gate;
  @override
  Future<(List<PropertySummary>, bool)> searchListings(Map<String, dynamic> filters,
      {int page = 1, CancelToken? cancelToken, bool refresh = false}) {
    if (filters['search'] == oldResultsInput) return gate.captureResults(cancelToken);
    if (filters['search'] == oldAiResult) {
      gate.forbiddenOldSearches++; throw StateError('Stale AI issued a results request');
    }
    return super.searchListings(filters, page: page, cancelToken: cancelToken, refresh: refresh);
  }
}

class CallbackApp extends ConsumerStatefulWidget {
  const CallbackApp({required this.gate, super.key});
  final CallbackGate gate;
  @override
  ConsumerState<CallbackApp> createState() => _CallbackAppState();
}
class _CallbackAppState extends ConsumerState<CallbackApp> {
  late final void Function(FlutterErrorDetails)? previousError;
  late final NoPaidAi blocker;
  @override
  void initState() {
    super.initState(); final g = widget.gate;
    g.actor = () => ref.read(authControllerProvider).asData?.value?.id;
    g.aiSession = () => ref.read(smartSearchSessionProvider.notifier);
    g.resultsSession = () => ref.read(homeSearchResultsProvider.notifier);
    blocker = NoPaidAi(); ref.read(dioProvider).interceptors.insert(0, blocker);
    ref.listenManual(authControllerProvider, (before, after) {
      if (before?.asData?.value?.id != after.asData?.value?.id) g.recordActor(after.asData?.value?.id);
    });
    previousError = FlutterError.onError;
    FlutterError.onError = (details) { g.errors++; previousError?.call(details); };
  }
  @override
  void dispose() { FlutterError.onError = previousError; super.dispose(); }
  @override
  Widget build(BuildContext context) => RealEstateApp(acceptanceWrapper: (context, child) =>
    CallbackPanel(gate: widget.gate, child: child));
}
class CallbackPanel extends ConsumerStatefulWidget {
  const CallbackPanel({required this.gate, required this.child, super.key});
  final CallbackGate gate; final Widget child;
  @override
  ConsumerState<CallbackPanel> createState() => _CallbackPanelState();
}
class _CallbackPanelState extends ConsumerState<CallbackPanel> {
  bool expanded = false;
  void run(FutureOr<void> Function() action) async {
    try { await action(); } catch (_) { widget.gate.errors++; widget.gate.changed(); }
  }
  void editor() {
    final g = widget.gate, id = widget.gate.actor();
    if (id != 66 && id != 26) throw StateError('Pinned editor actor required');
    final key = GlobalKey(); if (id == 26) g.editorB = key;
    final snapshot = <String, dynamic>{'editor_version':11,'draft_kind':'recovery','entry_method':'manual',
      'step':1,'type':'apartment','purpose':'rent','type_confirmed':true,'purpose_confirmed':true,
      'fields':{'title':id == 66 ? editorTitleA : editorTitleB}};
    final nav = ref.read(appRouterProvider).routerDelegate.navigatorKey.currentState;
    if (nav == null) throw StateError('Normal navigator required');
    setState(() => expanded = false);
    unawaited(nav.push<void>(MaterialPageRoute<void>(builder: (_) => PersonalListingCreationGate(
      child: ListingEditorScreen(key:key, localRecovery:snapshot, startFresh:true)))));
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation:widget.gate, builder:(context, _) {
    final g = widget.gate;
    Widget button(String label, FutureOr<void> Function() action) => TextButton(onPressed:()=>run(action),child:Text(label));
    return Stack(children:[widget.child, Positioned(top:MediaQuery.paddingOf(context).top + 4, left:8,
      child:Directionality(textDirection:TextDirection.ltr, child:Material(elevation:6, borderRadius:BorderRadius.circular(8),
        child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:300), child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextButton(onPressed:()=>setState(()=>expanded=!expanded),child:Text(expanded?'CB hide':'CB controls')),
          if(expanded) ...[
            const Text(callbackHarnessMarker,style:TextStyle(fontSize:8)),
            Wrap(children:[button('CB AI start',g.startAi),button('CB results start',g.startResults),button('CB editor',editor),
              button('CB seed B',g.seedB),button('CB release AI',g.releaseAi),button('CB release results',g.releaseResults),button('CB release GPS',g.releaseGps)]),
            Text(g.aiStatus),Text(g.resultsStatus),Text(g.gpsStatus),
            Semantics(label:'CB-META:${jsonEncode(g.metadata)}', child:const SizedBox(width:2,height:2)),
          ],
        ])))))]);
  });
}
