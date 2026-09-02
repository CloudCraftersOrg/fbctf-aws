using System.Web.Mvc;
using System.Web.Routing;

namespace ContosoScoreboard.Web
{
    public static class RouteConfig
    {
        public static void RegisterRoutes(RouteCollection routes)
        {
            routes.IgnoreRoute("{resource}.axd/{*pathInfo}");

            routes.MapRoute(
                name: "BadgeImage",
                url: "badge/{teamId}.png",
                defaults: new { controller = "Scoreboard", action = "Badge" });

            routes.MapRoute(
                name: "Default",
                url: "{controller}/{action}/{id}",
                defaults: new { controller = "Scoreboard", action = "Index", id = UrlParameter.Optional });
        }
    }
}
