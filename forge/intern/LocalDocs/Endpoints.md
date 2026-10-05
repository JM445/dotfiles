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
  - Getting all grading nodes associated to a scheme
  - Sync the associated grading_node tree to the scheme (add-only)
  - Get student list for a scheme

- Grading Nodes
  - Update a grading node
  - Get a grading node

- Discovered Tests
  - List discovered tests for an activity, an assignment or a classname
  - Get a discovered test

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

### Scheme

#### Scheme management

| REST TYPE | PATH | DESCRIPTION                             |
|-----------|------|-----------------------------------------|
| GET    | `/scheme/`             | Get a list of user accessible schemes   |
| GET    | `/scheme/{scheme_id}`  | Get a specific scheme                   |
| POST   | `/scheme/`             | Create a scheme                         |
| PUT    | `/scheme/{scheme_id}`  | Update a scheme                         |
| DELETE | `/scheme/{scheme_id}`  | Delete a scheme and ALL ASSOCIATED DATA |

#### Grading tree

| REST TYPE | PATH | DESCRIPTION                                                   |
|-----------|------|---------------------------------------------------------------|
| GET    | `/scheme/{scheme_id}/grading_node/` | Get the grading node tree of a scheme                         |
| POST   | `/scheme/{scheme_id}/tree/sync`     | Update the grading tree of a scheme with new discovered tests |

#### Students

| REST TYPE | PATH | DESCRIPTION                             |
|-----------|------|-----------------------------------------|
| GET    | `/scheme/{scheme_id}/logins/` | Get all logins associated with a scheme |
| GET    | `/scheme/{scheme_id}/groups/` | Get all groups associated with a scheme |

#### Grade reports

| REST TYPE | PATH                                                                               | DESCRIPTION                                                      |
|-----------|------------------------------------------------------------------------------------|------------------------------------------------------------------|
| GET    | `/scheme/{scheme_id}/grade_report?state=...&login=...&group=...`                   | Get a list of grade reports for a scheme, with filter options    |
| GET    | `/scheme/{scheme_id}/grade_report/{login}`                                         | Get a specific student's grade report                            |
| POST   | `/scheme/{scheme_id}/grade_report/{login}/compute`                                 | Update or create a grade report for a student                    |
| GET    | `/scheme/{scheme_id}/grade_report/export?format=csv\|xlsx&ignoreStale=true\|false` | Export a sheet with a syntesis of all grade reports for a scheme |

### Grading Nodes

| REST TYPE | PATH | DESCRIPTION                                                                                                    |
|-----------|------|----------------------------------------------------------------------------------------------------------------|
| GET    | `/grading_node/{node_id}` | Get info of a grading node                                                                                     |
| PUT    | `/grading_node/{node_id}` | Update info of a grading node (put refused if modifiing permanent fields: id, scheme_id, parent_id, reference) |

### Discovered Tests

| REST TYPE | PATH | DESCRIPTION                            |
|-----------|------|----------------------------------------|
| GET    | `/discovered_test/{test_id}`                                       | Get info on a specific discovered test |
| GET    | `/discovered_test?activityUri=...&assignmentUri=...&classname=...` | Might not be needed, keep for later    |

## TMP Notes