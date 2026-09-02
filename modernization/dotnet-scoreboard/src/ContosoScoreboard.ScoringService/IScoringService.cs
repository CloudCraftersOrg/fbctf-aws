using System.Runtime.Serialization;
using System.ServiceModel;

namespace ContosoScoreboard.ScoringService
{
    [ServiceContract]
    public interface IScoringService
    {
        [OperationContract]
        ScoreResult SubmitFlag(int teamId, string flag, string sourceIp);

        [OperationContract]
        int GetScore(int teamId);
    }

    [DataContract]
    public class ScoreResult
    {
        [DataMember]
        public bool Accepted { get; set; }

        [DataMember]
        public int NewScore { get; set; }

        [DataMember]
        public string Message { get; set; }
    }
}
