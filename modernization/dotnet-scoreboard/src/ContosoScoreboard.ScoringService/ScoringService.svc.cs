using System;
using System.Data.SqlClient;
using System.ServiceModel;

namespace ContosoScoreboard.ScoringService
{
    [ServiceBehavior(InstanceContextMode = InstanceContextMode.PerCall,
                     ConcurrencyMode = ConcurrencyMode.Multiple)]
    public class ScoringService : IScoringService
    {
        private static readonly string ConnString =
            System.Configuration.ConfigurationManager.ConnectionStrings["Scoreboard"].ConnectionString;

        public ScoreResult SubmitFlag(int teamId, string flag, string sourceIp)
        {
            using (var conn = new SqlConnection(ConnString))
            {
                conn.Open();
                using (var tx = conn.BeginTransaction())
                {
                    int points;
                    using (var cmd = new SqlCommand(
                        "SELECT Points FROM dbo.Flags WHERE FlagValue = @f AND IsActive = 1", conn, tx))
                    {
                        cmd.Parameters.AddWithValue("@f", flag);
                        var scalar = cmd.ExecuteScalar();
                        if (scalar == null)
                        {
                            return new ScoreResult { Accepted = false, Message = "no such flag" };
                        }
                        points = (int)scalar;
                    }

                    using (var dup = new SqlCommand(
                        "SELECT COUNT(*) FROM dbo.Captures WHERE TeamId = @t AND FlagValue = @f", conn, tx))
                    {
                        dup.Parameters.AddWithValue("@t", teamId);
                        dup.Parameters.AddWithValue("@f", flag);
                        if ((int)dup.ExecuteScalar() > 0)
                        {
                            return new ScoreResult { Accepted = false, Message = "already captured" };
                        }
                    }

                    using (var ins = new SqlCommand(
                        "INSERT INTO dbo.Captures (TeamId, FlagValue, SourceIp, CapturedUtc) " +
                        "VALUES (@t, @f, @ip, GETUTCDATE())", conn, tx))
                    {
                        ins.Parameters.AddWithValue("@t", teamId);
                        ins.Parameters.AddWithValue("@f", flag);
                        ins.Parameters.AddWithValue("@ip", sourceIp ?? (object)DBNull.Value);
                        ins.ExecuteNonQuery();
                    }

                    int newScore;
                    using (var upd = new SqlCommand(
                        "UPDATE dbo.Teams SET Score = Score + @p OUTPUT INSERTED.Score WHERE TeamId = @t", conn, tx))
                    {
                        upd.Parameters.AddWithValue("@p", points);
                        upd.Parameters.AddWithValue("@t", teamId);
                        newScore = (int)upd.ExecuteScalar();
                    }

                    tx.Commit();
                    return new ScoreResult { Accepted = true, NewScore = newScore, Message = "ok" };
                }
            }
        }

        public int GetScore(int teamId)
        {
            using (var conn = new SqlConnection(ConnString))
            {
                conn.Open();
                using (var cmd = new SqlCommand("SELECT Score FROM dbo.Teams WHERE TeamId = @t", conn))
                {
                    cmd.Parameters.AddWithValue("@t", teamId);
                    return (int)(cmd.ExecuteScalar() ?? 0);
                }
            }
        }
    }
}
