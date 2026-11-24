# FlowRecording

`FlowRecording` is the product for code that reads a flow outside a test bundle. It holds one type, `FlowRecorder`. The target depends on the `Flow` product and on nothing else, so it does not import `Testing` or `XCTest`, directly or through a dependency.

`FlowTesting` cannot do this job. `FlowTestingCore` imports `Testing`, and a module that links `Testing` cannot be linked into a UI-test host app, a preview or demo target, or a fixture executable. A shared test-support module that those targets link uses `FlowRecorder` in place of `probing`.

## What the recorder does

`FlowRecorder(_:)` takes a `Flow` or a `ThrowingFlow` and starts a task that collects it. Each value is appended to the record in emission order. `values` is the record so far. `isFinished` becomes `true` when the flow completes or fails, or when the recorder is cancelled. `failure` is the error of a throwing flow.

`values(atLeast:)` suspends until the record holds that many values, and returns the whole record. It returns what it has when the flow ends first, when `cancel()` is called, or when the waiting task is cancelled. A count of zero or less returns at once.

`cancel()` cancels the collection task and ends the record at once. A value or an error that the upstream produces after that call is dropped. Releasing the recorder cancels the collection task too, because the task holds the record and not the recorder.

## What it leaves out

The recorder has no assertions, no issue recording, no timeout, and no clock. A wait on a flow that stays open and never emits again parks until the caller cancels it. The caller bounds the wait.

The record is unbounded. Every value is kept until the recorder is released, so the type is for tests and fixtures and not for production code.

It does not replace `probing`. A test target that can link `FlowTesting` still reads flows with a `FlowReader`.

## The check

`TestingFreeProductTests` in `FlowArchitectureTests` walks every package target `FlowRecording` reaches, through the manifest and through source imports. It fails when one of them imports `Testing` or `XCTest`. The same walk over `FlowTesting` has to find the `Testing` import, so the check cannot pass by reading nothing.
