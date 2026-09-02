using System;
using System.Data.Entity;
using System.Web;
using System.Web.Mvc;
using System.Web.Routing;
using ContosoScoreboard.Web.Models;

namespace ContosoScoreboard.Web
{
    public class MvcApplication : HttpApplication
    {
        protected void Application_Start()
        {
            Database.SetInitializer(new CreateDatabaseIfNotExists<ScoreboardContext>());
            AreaRegistration.RegisterAllAreas();
            RouteConfig.RegisterRoutes(RouteTable.Routes);

            // Warm the badge cache directory (see Services/BadgeRenderer).
            var cacheDir = System.Configuration.ConfigurationManager.AppSettings["BadgeCachePath"];
            if (!System.IO.Directory.Exists(cacheDir))
            {
                System.IO.Directory.CreateDirectory(cacheDir);
            }
        }

        protected void Application_Error(object sender, EventArgs e)
        {
            var ex = Server.GetLastError();
            System.Diagnostics.Trace.TraceError("Unhandled: {0}", ex);
            Server.ClearError();
            Response.Redirect("~/Error");
        }

        protected void Session_Start(object sender, EventArgs e)
        {
            Session["StartedUtc"] = DateTime.UtcNow;
        }
    }
}
