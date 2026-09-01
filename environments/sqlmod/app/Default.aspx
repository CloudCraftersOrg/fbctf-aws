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
            Result.Text = newScore < 0
                ? "Unknown or inactive flag."
                : string.Format("Recorded. {0} is now on {1} points.", TeamPicker.SelectedItem.Text, newScore);
        }
        BindAll();
    }

    protected void AddTeam(object sender, EventArgs e)
    {
        if (NewTeamName.Text.Trim().Length == 0) return;
        using (var cn = new SqlConnection(Cs))
        using (var cmd = new SqlCommand("dbo.usp_UpsertTeam", cn) { CommandType = CommandType.StoredProcedure })
        {
            cmd.Parameters.AddWithValue("@Name", NewTeamName.Text.Trim());
            cmd.Parameters.AddWithValue("@CountryCode",
                NewTeamCountry.Text.Trim().Length == 2 ? (object)NewTeamCountry.Text.Trim().ToUpper() : DBNull.Value);
            cn.Open();
            cmd.ExecuteNonQuery();
        }
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
        Result.Text = "Ranks recalculated.";
    }
</script>
<!DOCTYPE html>
<html>
<head runat="server">
    <title>Contoso Scoreboard</title>
    <style>
        body { font: 15px/1.5 "Segoe UI", Arial, sans-serif; margin: 2rem auto; max-width: 880px; color: #1b1b1f; }
        h1 { font-size: 1.5rem; } h2 { font-size: 1.05rem; margin-top: 2rem; }
        table { border-collapse: collapse; width: 100%; } th, td { padding: 6px 10px; border-bottom: 1px solid #ddd; text-align: left; }
        th { background: #f3f3f5; } .panel { background: #f8f8fa; border: 1px solid #e3e3e8; padding: 1rem; margin-top: 1rem; }
        input, select { font: inherit; padding: 4px 6px; } .msg { color: #0a5; margin-left: 1rem; }
    </style>
</head>
<body>
<form id="f" runat="server">
    <h1>Contoso Scoreboard</h1>
    <p>ASP.NET Web Forms &middot; .NET Framework 4.8 &middot; SQL Server</p>

    <h2>Leaderboard</h2>
    <asp:GridView ID="Leaderboard" runat="server" AutoGenerateColumns="true" />

    <div class="panel">
        <h2>Record a capture</h2>
        Team <asp:DropDownList ID="TeamPicker" runat="server" />
        Flag <asp:TextBox ID="FlagValue" runat="server" placeholder="FLG-WEB-XSS-01" />
        <asp:Button runat="server" Text="Submit" OnClick="RecordCapture" />
        <asp:Label ID="Result" runat="server" CssClass="msg" />
    </div>

    <div class="panel">
        <h2>Add / update a team</h2>
        Name <asp:TextBox ID="NewTeamName" runat="server" />
        Country <asp:TextBox ID="NewTeamCountry" runat="server" placeholder="US" />
        <asp:Button runat="server" Text="Save" OnClick="AddTeam" />
        <asp:Button runat="server" Text="Recalculate ranks" OnClick="RecalcRanks" />
    </div>
</form>
</body>
</html>
