using System;
using System.Linq;
using System.ServiceModel;
using System.Web.Mvc;
using ContosoScoreboard.ScoringService;
using ContosoScoreboard.Web.Models;
using ContosoScoreboard.Web.Services;

namespace ContosoScoreboard.Web.Controllers
{
    public class ScoreboardController : Controller
    {
        private readonly ScoreboardContext _db = ScoreboardContext.Current;

        public ActionResult Index()
        {
            var teams = _db.Teams
                .Where(t => !t.IsDisqualified)
                .OrderByDescending(t => t.Score)
                .ThenBy(t => t.LastCaptureUtc)
                .ToList();

            ViewBag.GeneratedUtc = DateTime.UtcNow;
            ViewBag.Viewer = User.Identity.IsAuthenticated ? User.Identity.Name : "guest";
            return View(teams);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Capture(int teamId, string flag)
        {
            var url = System.Configuration.ConfigurationManager.AppSettings["ScoringServiceUrl"];
            var binding = new BasicHttpBinding { MaxReceivedMessageSize = 2097152 };
            var factory = new ChannelFactory<IScoringService>(binding, new EndpointAddress(url));
            var client = factory.CreateChannel();

            ScoreResult result;
            try
            {
                result = client.SubmitFlag(teamId, flag, Request.UserHostAddress);
            }
            catch (CommunicationException ex)
            {
                System.Diagnostics.Trace.TraceError("scoring call failed: {0}", ex);
                return new HttpStatusCodeResult(502);
            }

            if (result.Accepted)
            {
                var team = _db.Teams.Find(teamId);
                team.Score = result.NewScore;
                team.LastCaptureUtc = DateTime.UtcNow;
                _db.SaveChanges();
            }

            return Json(new { result.Accepted, result.NewScore, result.Message });
        }

        [OutputCache(Duration = 60, VaryByParam = "teamId")]
        public ActionResult Badge(int teamId)
        {
            var ordered = _db.Teams.Where(t => !t.IsDisqualified)
                .OrderByDescending(t => t.Score).ToList();
            var team = ordered.FirstOrDefault(t => t.TeamId == teamId);
            if (team == null)
            {
                return HttpNotFound();
            }

            var png = BadgeRenderer.Render(team.Name, team.Score, ordered.IndexOf(team) + 1);
            return File(png, "image/png");
        }
    }
}
