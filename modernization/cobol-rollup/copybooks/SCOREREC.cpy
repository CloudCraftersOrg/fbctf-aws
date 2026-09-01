      *--------------------------------------------------------------*
      * SCOREREC - one flag-capture event from the app tier export.   *
      * Fixed width 40 bytes, LINE SEQUENTIAL, zoned decimal (the     *
      * packed COMP-3 layout is in TEAMREC and rollup working store). *
      *--------------------------------------------------------------*
       01  SCORE-RECORD.
           05  SR-TEAM-ID              PIC 9(05).
           05  SR-FLAG-CODE            PIC X(12).
           05  SR-POINTS               PIC 9(05).
           05  SR-CAPTURED-TS          PIC X(14).
           05  SR-STATUS              PIC X(01).
               88  SR-STATUS-OK        VALUE 'A'.
               88  SR-STATUS-VOID      VALUE 'V'.
           05  FILLER                  PIC X(03).
