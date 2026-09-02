<%@ Page Language="C#" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Configuration" %>
<script runat="server">
    // Contoso Scoreboard - classic ASP.NET Web Forms on .NET Framework 4.8.
    // Data access is inline ADO.NET against SQL Server stored procedures; the
    // connection string lives in web.config. This is the pre-modernization
    // shape AWS Transform's SQL Server -> Aurora job converts (Web Forms has no
    // .NET Core successor, System.Data.SqlClient -> Microsoft.Data.SqlClient,
    // T-SQL procs -> PL/pgSQL, web.config -> appsettings.json).

    string Cs { get { return ConfigurationManager.ConnectionStrings["Scoreboard"].ConnectionString; } }

    protected void Page_Load(object sender, EventArgs e)
    {
        if (!IsPostBack) BindAll();
    }

    void BindAll()
    {
        using (var cn = new SqlConnection(Cs))
        {
            cn.Open();

            var board = new DataTable();
            new SqlDataAdapter("SELECT Name, Score, RankBucket, Captures, ActiveMinutes FROM dbo.vw_Leaderboard", cn).Fill(board);
            Leaderboard.DataSource = board;
            Leaderboard.DataBind();

            var teams = new DataTable();
            new SqlDataAdapter("SELECT TeamId, Name FROM dbo.Teams WHERE IsDisqualified = 0 ORDER BY Name", cn).Fill(teams);
            TeamPicker.DataSource = teams;
            TeamPicker.DataTextField = "Name";
            TeamPicker.DataValueField = "TeamId";
            TeamPicker.DataBind();

            TeamCount.Text = teams.Rows.Count.ToString();
        }
    }

    protected void RecordCapture(object sender, EventArgs e)
    {
        using (var cn = new SqlConnection(Cs))
        using (var cmd = new SqlCommand("dbo.usp_RecordCapture", cn) { CommandType = CommandType.StoredProcedure })
        {
            cmd.Parameters.AddWithValue("@TeamId", int.Parse(TeamPicker.SelectedValue));
            cmd.Parameters.AddWithValue("@FlagValue", FlagValue.Text.Trim());
            cmd.Parameters.AddWithValue("@SourceIp", Request.UserHostAddress ?? "");
            var outScore = new SqlParameter("@NewScore", SqlDbType.Int) { Direction = ParameterDirection.Output };
            cmd.Parameters.Add(outScore);

            cn.Open();
            cmd.ExecuteNonQuery();
            int newScore = (int)outScore.Value;
            SetMsg(newScore < 0
                ? "Unknown or inactive flag."
                : string.Format("Recorded. {0} is now on {1} points.", TeamPicker.SelectedItem.Text, newScore),
                newScore >= 0);
        }
        FlagValue.Text = "";
        BindAll();
    }

    protected void AddTeam(object sender, EventArgs e)
    {
        if (NewTeamName.Text.Trim().Length == 0) { SetMsg("Enter a team name.", false); return; }
        using (var cn = new SqlConnection(Cs))
        using (var cmd = new SqlCommand("dbo.usp_UpsertTeam", cn) { CommandType = CommandType.StoredProcedure })
        {
            cmd.Parameters.AddWithValue("@Name", NewTeamName.Text.Trim());
            cmd.Parameters.AddWithValue("@CountryCode",
                NewTeamCountry.Text.Trim().Length == 2 ? (object)NewTeamCountry.Text.Trim().ToUpper() : DBNull.Value);
            cn.Open();
            cmd.ExecuteNonQuery();
        }
        SetMsg("Saved team " + NewTeamName.Text.Trim() + ".", true);
        NewTeamName.Text = NewTeamCountry.Text = "";
        BindAll();
    }

    protected void RecalcRanks(object sender, EventArgs e)
    {
        using (var cn = new SqlConnection(Cs))
        using (var cmd = new SqlCommand("dbo.usp_RecalculateRanks", cn) { CommandType = CommandType.StoredProcedure })
        {
            cn.Open();
            cmd.ExecuteNonQuery();
        }
        SetMsg("Ranks recalculated.", true);
        BindAll();
    }

    void SetMsg(string text, bool good)
    {
        Result.Text = text;
        Result.CssClass = good ? "msg ok" : "msg err";
    }
</script>
<!DOCTYPE html>
<html>
<head runat="server">
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Contoso Scoreboard</title>
    <style>
        :root { --line: #e2e2e8; --ink: #1b1b1f; --muted: #6b6b76; --accent: #1f6feb; --bg: #f6f7f9; }
        * { box-sizing: border-box; }
        body { font: 15px/1.55 -apple-system, "Segoe UI", Roboto, Arial, sans-serif; color: var(--ink);
               background: var(--bg); margin: 0; padding: 2.5rem 1rem; }
        .wrap { max-width: 860px; margin: 0 auto; }
        header { border-bottom: 2px solid var(--ink); padding-bottom: .6rem; margin-bottom: 1.5rem; }
        h1 { font-size: 1.5rem; margin: 0; }
        header p { margin: .25rem 0 0; color: var(--muted); font-size: .85rem; letter-spacing: .02em; }
        h2 { font-size: .95rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted);
             margin: 0 0 .75rem; }
        .card { background: #fff; border: 1px solid var(--line); border-radius: 8px; padding: 1.25rem 1.4rem;
                margin-bottom: 1.25rem; }
        table.grid { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
        table.grid th { text-align: left; font-size: .78rem; text-transform: uppercase; letter-spacing: .05em;
                        color: var(--muted); border-bottom: 2px solid var(--line); padding: .5rem .6rem; }
        table.grid td { padding: .55rem .6rem; border-bottom: 1px solid var(--line); }
        table.grid tr:last-child td { border-bottom: none; }
        table.grid td:nth-child(2), table.grid th:nth-child(2),
        table.grid td:nth-child(4), table.grid th:nth-child(4),
        table.grid td:nth-child(5), table.grid th:nth-child(5) { text-align: right; }
        .field { display: inline-flex; flex-direction: column; gap: .2rem; margin: 0 1rem .6rem 0; vertical-align: top; }
        .field label { font-size: .78rem; color: var(--muted); }
        input, select { font: inherit; padding: .4rem .55rem; border: 1px solid var(--line); border-radius: 6px;
                        background: #fff; min-width: 11rem; }
        .btn { font: inherit; padding: .45rem .9rem; border: 1px solid var(--accent); background: var(--accent);
               color: #fff; border-radius: 6px; cursor: pointer; }
        .btn.secondary { background: #fff; color: var(--accent); }
        .msg { display: inline-block; margin-left: .75rem; font-size: .9rem; }
        .msg.ok { color: #137333; } .msg.err { color: #c5221f; }
        footer { color: var(--muted); font-size: .8rem; margin-top: 1.5rem; }
    </style>
</head>
<body>
<form id="f" runat="server">
    <div class="wrap">
        <header>
            <h1>Contoso Scoreboard</h1>
            <p>ASP.NET Web Forms &middot; .NET Framework 4.8 &middot; SQL Server 2022</p>
        </header>

        <div class="card">
            <h2>Leaderboard &mdash; <asp:Literal ID="TeamCount" runat="server" /> teams</h2>
            <asp:GridView ID="Leaderboard" runat="server" AutoGenerateColumns="true"
                          GridLines="None" CssClass="grid" />
        </div>

        <div class="card">
            <h2>Record a capture</h2>
            <span class="field"><label>Team</label><asp:DropDownList ID="TeamPicker" runat="server" /></span>
            <span class="field"><label>Flag code</label><asp:TextBox ID="FlagValue" runat="server" placeholder="FLG-WEB-XSS-01" /></span>
            <asp:Button runat="server" CssClass="btn" Text="Submit capture" OnClick="RecordCapture" />
            <asp:Label ID="Result" runat="server" CssClass="msg" />
        </div>

        <div class="card">
            <h2>Add / update a team</h2>
            <span class="field"><label>Name</label><asp:TextBox ID="NewTeamName" runat="server" /></span>
            <span class="field"><label>Country (2-letter)</label><asp:TextBox ID="NewTeamCountry" runat="server" placeholder="US" /></span>
            <asp:Button runat="server" CssClass="btn" Text="Save team" OnClick="AddTeam" />
            <asp:Button runat="server" CssClass="btn secondary" Text="Recalculate ranks" OnClick="RecalcRanks" />
        </div>

        <footer>Reads <code>dbo.vw_Leaderboard</code>; writes via <code>usp_UpsertTeam</code>, <code>usp_RecordCapture</code>, <code>usp_RecalculateRanks</code>.</footer>
    </div>
</form>
</body>
</html>
