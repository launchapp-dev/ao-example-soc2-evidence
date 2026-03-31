# Independent Practitioner's Report on Management's Description of
# {{ORGANIZATION}}'s System and the Suitability of the Design and
# Operating Effectiveness of Controls

**Prepared for:** {{AUDITOR}}
**Prepared by:** Management of {{ORGANIZATION}}
**Report Date:** {{REPORT_DATE}}
**Examination Period:** {{AUDIT_START}} through {{AUDIT_END}}

---

## Section I: Management's Description of the System

### 1. Overview of Services

{{ORGANIZATION}} provides {{SERVICE_DESCRIPTION}}. The system boundary includes
the following components and repositories: {{REPOS_IN_SCOPE}}.

### 2. Principal Service Commitments and System Requirements

Management has identified the following principal service commitments to users:

{{SERVICE_COMMITMENTS}}

### 3. Components of the System

**Infrastructure:** {{INFRASTRUCTURE_DESCRIPTION}}

**Software:** {{SOFTWARE_DESCRIPTION}}

**People:** {{PEOPLE_DESCRIPTION}}

**Processes:** The organization follows formal software development lifecycle (SDLC)
procedures including code review, automated testing, and deployment approvals.

**Data:** {{DATA_DESCRIPTION}}

---

## Section II: Management's Assertion

Management of {{ORGANIZATION}} asserts that:

1. The description in Section I fairly presents the system that was designed and
   implemented throughout the period {{AUDIT_START}} through {{AUDIT_END}}, based
   on the criteria set forth in the AICPA's description criteria.

2. The controls related to the trust service categories included in the description
   were suitably designed to provide reasonable assurance that {{ORGANIZATION}}'s
   service commitments and system requirements would be achieved based on the
   applicable trust service criteria.

3. The controls operated effectively throughout the period {{AUDIT_START}} through
   {{AUDIT_END}} to achieve {{ORGANIZATION}}'s service commitments and system
   requirements based on the applicable trust service criteria, **with exceptions
   noted in Section IV**.

---

## Section III: Test Results by Trust Service Category

### Security (Common Criteria)

| Criterion | Description | Result | Exceptions |
|---|---|---|---|
{{CC_TEST_RESULTS}}

### Availability

| Criterion | Description | Result | Exceptions |
|---|---|---|---|
{{A_TEST_RESULTS}}

### Processing Integrity

| Criterion | Description | Result | Exceptions |
|---|---|---|---|
{{PI_TEST_RESULTS}}

### Confidentiality

| Criterion | Description | Result | Exceptions |
|---|---|---|---|
{{C_TEST_RESULTS}}

### Privacy

| Criterion | Description | Result | Exceptions |
|---|---|---|---|
{{P_TEST_RESULTS}}

---

## Section IV: Exceptions and Remediation

{{EXCEPTIONS_SECTION}}

---

## Section V: Complementary User Entity Controls

Users of {{ORGANIZATION}}'s system must implement the following controls to
rely on the effectiveness of the above controls:

{{CUEC_LIST}}

---

## Appendix: Evidence Inventory

See `output/evidence-index.md` for the complete numbered inventory of evidence
collected and referenced in this report.

---

*This report was prepared using the AO SOC 2 Evidence Collector.*
*Evidence was collected via automated tooling (GitHub API, git CLI) and normalized*
*by AI agents on {{COLLECTION_DATE}}.*
