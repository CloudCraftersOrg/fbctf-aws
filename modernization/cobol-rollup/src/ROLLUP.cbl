       IDENTIFICATION DIVISION.
       PROGRAM-ID. ROLLUP.
      *--------------------------------------------------------------*
      * Nightly score rollup for the CTF scoreboard.                  *
      *   INPUT  : SCOREIN  capture events (SCOREREC, 40 bytes)       *
      *   OUTPUT : TEAMOUT  ranked team totals (TEAMREC)              *
      *            RPTOUT   control report                            *
      * Runs on finance-batch-01. Converted target: Java batch job.   *
      *--------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SCORE-IN ASSIGN TO SCOREIN
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-IN-STATUS.
           SELECT TEAM-OUT ASSIGN TO TEAMOUT
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-OUT-STATUS.
           SELECT RPT-OUT ASSIGN TO RPTOUT
               ORGANIZATION IS LINE SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  SCORE-IN.
           COPY SCOREREC.
       FD  TEAM-OUT.
           COPY TEAMREC.
       FD  RPT-OUT.
       01  RPT-LINE                PIC X(80).

       WORKING-STORAGE SECTION.
       01  WS-FLAGS.
           05  WS-IN-STATUS        PIC X(02) VALUE '00'.
           05  WS-OUT-STATUS       PIC X(02) VALUE '00'.
           05  WS-EOF              PIC X(01) VALUE 'N'.
               88  END-OF-INPUT    VALUE 'Y'.

       01  WS-COUNTERS.
           05  WS-READ-CT          PIC 9(07) COMP VALUE ZERO.
           05  WS-VOID-CT          PIC 9(07) COMP VALUE ZERO.
           05  WS-TEAM-CT          PIC 9(05) COMP VALUE ZERO.
           05  WS-I               PIC 9(05) COMP VALUE ZERO.
           05  WS-J               PIC 9(05) COMP VALUE ZERO.

       01  WS-TEAM-TABLE.
           05  WS-ENTRY OCCURS 500 TIMES INDEXED BY WT-IX.
               10  WT-TEAM-ID      PIC 9(05).
               10  WT-TOTAL        PIC S9(07) COMP-3.
               10  WT-COUNT        PIC 9(04).
               10  WT-LAST-TS      PIC X(14).
               10  WT-DQ           PIC X(01).

       01  WS-DQ-THRESHOLD         PIC S9(07) COMP-3 VALUE 200.
       01  WS-NUM-ED               PIC ZZZZZZ9.
       01  WS-SWAP.
           05  SW-TEAM-ID          PIC 9(05).
           05  SW-TOTAL            PIC S9(07) COMP-3.
           05  SW-COUNT            PIC 9(04).
           05  SW-LAST-TS          PIC X(14).
           05  SW-DQ               PIC X(01).

       PROCEDURE DIVISION.
       0000-MAIN.
           PERFORM 1000-OPEN-FILES
           PERFORM 2000-LOAD-CAPTURES THRU 2000-EXIT
               UNTIL END-OF-INPUT
           PERFORM 3000-APPLY-DQ-RULE
               VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-TEAM-CT
           PERFORM 4000-SORT-DESCENDING
           PERFORM 5000-WRITE-RANKED
           PERFORM 6000-WRITE-REPORT
           PERFORM 9000-CLOSE-FILES
           STOP RUN.

       1000-OPEN-FILES.
           OPEN INPUT SCORE-IN
           OPEN OUTPUT TEAM-OUT
           OPEN OUTPUT RPT-OUT
           IF WS-IN-STATUS NOT = '00'
               DISPLAY 'ROLLUP: open SCOREIN failed ' WS-IN-STATUS
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF.

       2000-LOAD-CAPTURES.
           READ SCORE-IN
               AT END
                   SET END-OF-INPUT TO TRUE
                   GO TO 2000-EXIT
           END-READ
           ADD 1 TO WS-READ-CT
           IF SR-STATUS-VOID
               ADD 1 TO WS-VOID-CT
               GO TO 2000-EXIT
           END-IF
           PERFORM 2100-ACCUMULATE.
       2000-EXIT.
           EXIT.

       2100-ACCUMULATE.
           SET WT-IX TO 1
           SEARCH WS-ENTRY VARYING WT-IX
               AT END
                   PERFORM 2200-ADD-TEAM
               WHEN WT-TEAM-ID (WT-IX) = SR-TEAM-ID
                   ADD SR-POINTS TO WT-TOTAL (WT-IX)
                   ADD 1 TO WT-COUNT (WT-IX)
                   IF SR-CAPTURED-TS > WT-LAST-TS (WT-IX)
                       MOVE SR-CAPTURED-TS TO WT-LAST-TS (WT-IX)
                   END-IF
           END-SEARCH.

       2200-ADD-TEAM.
           ADD 1 TO WS-TEAM-CT
           MOVE SR-TEAM-ID TO WT-TEAM-ID (WS-TEAM-CT)
           MOVE SR-POINTS TO WT-TOTAL (WS-TEAM-CT)
           MOVE 1 TO WT-COUNT (WS-TEAM-CT)
           MOVE SR-CAPTURED-TS TO WT-LAST-TS (WS-TEAM-CT)
           MOVE 'N' TO WT-DQ (WS-TEAM-CT).

       3000-APPLY-DQ-RULE.
           IF WT-TOTAL (WS-I) > WS-DQ-THRESHOLD
               MOVE 'Y' TO WT-DQ (WS-I)
           END-IF.

       4000-SORT-DESCENDING.
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I >= WS-TEAM-CT
               PERFORM VARYING WS-J FROM 1 BY 1
                   UNTIL WS-J > WS-TEAM-CT - WS-I
                   IF WT-TOTAL (WS-J) < WT-TOTAL (WS-J + 1)
                       MOVE WS-ENTRY (WS-J) TO WS-SWAP
                       MOVE WS-ENTRY (WS-J + 1) TO WS-ENTRY (WS-J)
                       MOVE WS-SWAP TO WS-ENTRY (WS-J + 1)
                   END-IF
               END-PERFORM
           END-PERFORM.

       5000-WRITE-RANKED.
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-TEAM-CT
               MOVE WS-I TO TR-RANK
               MOVE WT-TEAM-ID (WS-I) TO TR-TEAM-ID
               MOVE WT-TOTAL (WS-I) TO TR-TOTAL-POINTS
               MOVE WT-COUNT (WS-I) TO TR-CAPTURE-COUNT
               MOVE WT-LAST-TS (WS-I) TO TR-LAST-CAPTURE-TS
               MOVE WT-DQ (WS-I) TO TR-DQ-FLAG
               WRITE TEAM-RECORD
           END-PERFORM.

       6000-WRITE-REPORT.
           MOVE SPACES TO RPT-LINE
           MOVE 'ROLLUP CONTROL REPORT' TO RPT-LINE
           WRITE RPT-LINE
           MOVE WS-READ-CT TO WS-NUM-ED
           MOVE SPACES TO RPT-LINE
           STRING 'RECORDS READ : ' WS-NUM-ED
               DELIMITED BY SIZE INTO RPT-LINE
           WRITE RPT-LINE
           MOVE WS-VOID-CT TO WS-NUM-ED
           MOVE SPACES TO RPT-LINE
           STRING 'VOID SKIPPED : ' WS-NUM-ED
               DELIMITED BY SIZE INTO RPT-LINE
           WRITE RPT-LINE
           MOVE WS-TEAM-CT TO WS-NUM-ED
           MOVE SPACES TO RPT-LINE
           STRING 'TEAMS RANKED : ' WS-NUM-ED
               DELIMITED BY SIZE INTO RPT-LINE
           WRITE RPT-LINE.

       9000-CLOSE-FILES.
           CLOSE SCORE-IN
           CLOSE TEAM-OUT
           CLOSE RPT-OUT.
