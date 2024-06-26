import 'package:flutter/material.dart';
import 'package:sama/backend/storage/memories.dart';
import 'package:uuid/uuid.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/backend/api_requests/api_calls.dart';
import '/backend/backend.dart';
import '/backend/push_notifications/push_notifications_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/actions/index.dart' as actions;
import '/flutter_flow/custom_functions.dart' as functions;

// Perform actions periodically
Future<void> periodicAction(BuildContext context) async {
  String lastWords = actions.getLastWords();
  if (lastWords.isNotEmpty) {
    updateLastMemory(lastWords);
    await memoryCreationBlock(context);
  }
}

// Perform final actions on finish
Future<void> onFinishAction(BuildContext context) async {
  periodicAction(context);
  triggerFinishNotification();
}

void updateLastMemory(String lastWords) {
  FFAppState().lastMemory = lastWords;
  debugPrint('FFAppState().lastMemory ${FFAppState().lastMemory}');
  // TODO: retrieve most recent memory (previous) and do a few tokens overlapping with the new one.
}

// Process the creation of memory records
Future<void> memoryCreationBlock(BuildContext context) async {
  changeAppStateMemoryCreating();
  var structuredMemory = await structureMemory();
  debugPrint('Structured Memory: $structuredMemory');
  if (structuredMemory.contains("N/A")) {
    await saveFailureMemory(structuredMemory);
  } else {
    await finalizeMemoryRecord(structuredMemory);
  }
}

// Call to the API to get structured memory
Future<String> structureMemory() async {
  logFirebaseEvent('memoryCreationBlock_StructureMemoryAPI');
  return await generateTitleAndSummaryForMemory(FFAppState().lastMemory);
}

// Save failure memory when structured memory contains NA
Future<void> saveFailureMemory(String structuredMemory) async {
  MemoryRecord memory = MemoryRecord(
      id: const Uuid().v4(),
      date: DateTime.now(),
      rawMemory: FFAppState().lastMemory,
      structuredMemory: structuredMemory,
      isEmpty: FFAppState().lastMemory == '',
      isUseless: true);
  MemoryStorage.addMemory(memory);
}

// Update app state when starting memory processing
void changeAppStateMemoryCreating() {
  logFirebaseEvent('memoryCreationBlock_update_app_state');
  FFAppState().update(() {
    FFAppState().memoryCreationProcessing = !FFAppState().memoryCreationProcessing;
  });
}

// Finalize memory record after processing feedback
Future<void> finalizeMemoryRecord(String structuredMemory) async {
  MemoryRecord memoryRecord = await createMemoryRecord(structuredMemory);
  changeAppStateMemoryCreating();
  List<double> vector = await getEmbeddingsFromInput(structuredMemory);
  await storeVectorData(memoryRecord, vector);
}

// Create memory record
Future<MemoryRecord> createMemoryRecord(String structuredMemory) async {
  var memory = MemoryRecord(
      id: const Uuid().v4(),
      date: DateTime.now(),
      rawMemory: FFAppState().lastMemory,
      structuredMemory: structuredMemory,
      isEmpty: FFAppState().lastMemory == '',
      isUseless: false);
  MemoryStorage.addMemory(memory);
  return memory;
}

// Store vector data after memory record creation
Future<void> storeVectorData(MemoryRecord memoryRecord, List<double> vector) async {
  // debugPrint('storeVectorData: memoryRecord -> $memoryRecord');
  // debugPrint('storeVectorData: vectorResponse -> ${vectorResponse.jsonBody}');

  await createPineconeVector(
    vector,
    memoryRecord.structuredMemory,
    memoryRecord.id,
  );
  // debugPrint('storeVectorData VectorAdded: ${vectorAdded.statusCode} ${vectorAdded.jsonBody}');
  // TODO: never triggers because `toShowToUserShowHide` is always 'Hide', because feedback logic was removed.
  // if (memoryRecord.toShowToUserShowHide == 'Show' && !memoryRecord.emptyMemory && !memoryRecord.isUselessMemory) {
  //   logFirebaseEvent('memoryCreationBlock_trigger_push_notific');
  //   if (currentUserReference != null) {
  //     triggerPushNotification(
  //       notificationTitle: 'Sama',
  //       notificationText: FFAppState().feedback,
  //       userRefs: [currentUserReference!],
  //       initialPageName: 'chat',
  //       parameterData: {},
  //     );
  //   }
  // }
}

// Fetch latest valid memories
Future<List<MemoriesRecord>> fetchLatestMemories() async {
  logFirebaseEvent('voiceCommandBlock_firestore_query');
  return await queryMemoriesRecordOnce(
    queryBuilder: (memoriesRecord) => memoriesRecord
        .where('user', isEqualTo: currentUserReference)
        .where('isUselessMemory', isEqualTo: false)
        .where('emptyMemory', isEqualTo: false)
        .orderBy('date', descending: true),
    limit: 30,
  );
}

// Trigger notification to indicate recording is disabled
void triggerFinishNotification() {
  logFirebaseEvent('OnFinishAction_trigger_push_notification');
  if (currentUserReference != null) {
    triggerPushNotification(
      notificationTitle: 'Sama',
      notificationText: 'Recording is disabled! Please restart audio recording',
      userRefs: [currentUserReference!],
      initialPageName: 'chat',
      parameterData: {},
    );
  }
}
