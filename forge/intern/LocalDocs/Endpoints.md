# Grading System - Endpoints definition

### Disclaimer

This document is a working document and is subject to evolution. It helps me organizing my mind and should not be taken as a source of absolute truth.

## Frontend - What should it be able to do (brainstorm)

Frontend features will be designed to let teachers build their own grading schemes and configure anything needed to compute grades.
This includes:

- Scheme
  - Creating a new GradingScheme with its information
  - Updating an existing GradingScheme
  - Listing schemes
  - Getting a scheme
  - Delete a scheme and all its reports & associated nodes

- Grading Nodes
  - Create a grading node ? This might not be a good idea as the grading node tree is independent from teacher's will
  - Update a grading node
  - Get a grading node
  - Generate the GradingNode tree (but how ? by building it from assignments data, test results and default values ? manually created by teachers ?)

- Discovered Tests
  - List discovered tests for a ? submissionDef ? activity ? student ? grading node ?
  - Get a discovered test

- Students
  - Get student list for a scheme

- Assignments
  - List assignments
  - Get assignment

- Submission Definition
  - List
  - Get

- GradeReports
  - Start grading computation for one student and a specific grading scheme
  - Start grading computation for all students of a specific grading scheme (this could take a lot of time and might be better done from frontend with multiple rest calls. This way a loading status can be computed and displayed)
  - Start grading computation for all stale reports of a scheme
  - Get a grade report for a student and a scheme
  - Get all stale grade reports for a scheme
  - List all reports for a scheme

- Export (reports could be long to process, how could I manage an asynchronous report exportation, with ETA and status ?)
  - Start exporting reports for a scheme
  - Get report exportation status ?
  - Get report exportation result

## Frontend - Endpoints list

- Scheme
  - GET /



## TMP Notes