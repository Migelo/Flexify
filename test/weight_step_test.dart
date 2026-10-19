import 'package:drift/drift.dart' hide isNull;
import 'package:flexify/database/database.dart';
import 'package:flexify/plan/exercise_modal.dart';
import 'package:flexify/plan/start_plan_page.dart';
import 'package:flexify/plan/workout_sessions.dart';
import 'package:flexify/stepper_field.dart';
import 'package:flexify/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/fixtures.dart';
import 'support/test_app.dart';

Finder stepperWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is StepperField && widget.labelText == label,
);

Finder editableIn(Finder ancestor) =>
    find.descendant(of: ancestor, matching: find.byType(EditableText));

void main() {
  test('weightStep keeps the automatic step per equipment type', () {
    expect(weightStep('Dumbbell curl', 'kg'), 2);
    expect(weightStep('Cable row', 'kg'), 5);
    expect(weightStep('Leg press', 'kg'), 10);
    expect(weightStep('Bench press', 'kg'), 2.5);
    expect(weightStep('Bench press', 'lb'), 5);
    expect(weightStep('Dumbbell curl', 'lb'), 5);
  });

  test('weightStep uses the per-exercise step when set', () {
    expect(weightStep('Bench press', 'kg', stepKg: 1.25), 1.25);
    expect(weightStep('Dumbbell curl', 'kg', stepKg: 0.5), 0.5);
    expect(weightStep('Bench press', 'lb', stepKg: 1.25), closeTo(2.76, 0.01));
  });

  test('exercise keeps its custom weight step', () async {
    final harness = await FlexifyTestHarness.create();
    final database = harness.database;
    final exercise = await ensureExerciseFixture(database, 'Bench press');

    expect(exercise.weightStepKg, isNull);

    await (database.exercises.update()
          ..where((row) => row.id.equals(exercise.id)))
        .write(const ExercisesCompanion(weightStepKg: Value(1.25)));

    final updated =
        await (database.exercises.select()
              ..where((row) => row.id.equals(exercise.id)))
            .getSingle();
    expect(updated.weightStepKg, 1.25);
  });

  testWidgets('ExerciseModal stores and clears a custom weight step', (
    WidgetTester tester,
  ) async {
    final harness = await FlexifyTestHarness.create();
    final database = harness.database;
    final planId = await database.plans.insertOne(planFixture());
    final exercise = await ensureExerciseFixture(database, 'Bench press');
    final planExercise = await database.planExercises.insertReturning(
      planExerciseFixture(planId: planId, exerciseId: exercise.id),
    );
    final workout = await resumeOrStartWorkout(database, planId);

    await harness.pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  body: ExerciseModal(
                    planExerciseId: planExercise.id,
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    workoutId: workout.id,
                    hasData: false,
                    onSelect: () {},
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Weight step (kg)'), findsOneWidget);

    final field = editableIn(
      find.widgetWithText(TextField, 'Weight step (kg)'),
    );
    await tester.enterText(field, '1.25');
    await tester.pumpAndSettle();

    final stored =
        await (database.exercises.select()
              ..where((row) => row.id.equals(exercise.id)))
            .getSingle();
    expect(stored.weightStepKg, 1.25);

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();

    final reset =
        await (database.exercises.select()
              ..where((row) => row.id.equals(exercise.id)))
            .getSingle();
    expect(reset.weightStepKg, isNull);
  });

  testWidgets('StartPlanPage steps the weight by the custom step', (
    WidgetTester tester,
  ) async {
    final harness = await FlexifyTestHarness.create();
    final database = harness.database;
    final planId = await database.plans.insertOne(planFixture(title: 'Plan'));
    await insertPlanExerciseFixture(
      database,
      planId: planId,
      exercise: 'Bench press',
    );

    final exercise =
        await (database.exercises.select()
              ..where((row) => row.name.equals('Bench press')))
            .getSingle();
    await (database.exercises.update()
          ..where((row) => row.id.equals(exercise.id)))
        .write(const ExercisesCompanion(weightStepKg: Value(1.25)));

    final plan =
        await (database.plans.select()..where((row) => row.id.equals(planId)))
            .getSingle();
    final planExercise =
        await (database.planExercises.select()
              ..where((row) => row.planId.equals(planId)))
            .getSingle();
    final updated =
        await (database.exercises.select()
              ..where((row) => row.id.equals(exercise.id)))
            .getSingle();

    await harness.pump(
      tester,
      StartPlanPage(
        plan: plan,
        initial: [
          PlanExerciseEntry(planExercise: planExercise, exercise: updated),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final weight = stepperWithLabel('Weight (kg)');
    expect(weight, findsOneWidget);

    await tester.tap(
      find.descendant(of: weight, matching: find.byIcon(Icons.add)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(editableIn(weight)).controller.text,
      '1.25',
    );
  });
}
