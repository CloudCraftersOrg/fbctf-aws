      *--------------------------------------------------------------*
      * TEAMREC - ranked per-team total, written to the rollup out.   *
      *--------------------------------------------------------------*
       01  TEAM-RECORD.
           05  TR-RANK                 PIC 9(03).
           05  TR-TEAM-ID              PIC 9(05).
           05  TR-TOTAL-POINTS         PIC S9(07) COMP-3.
           05  TR-CAPTURE-COUNT        PIC 9(04).
           05  TR-LAST-CAPTURE-TS      PIC X(14).
           05  TR-DQ-FLAG              PIC X(01).
               88  TR-DISQUALIFIED     VALUE 'Y'.
               88  TR-ELIGIBLE         VALUE 'N'.
