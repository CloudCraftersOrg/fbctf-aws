using System.Data.Entity;

namespace ContosoScoreboard.Web.Models
{
    public class ScoreboardContext : DbContext
    {
        // One shared context for the whole app — the pattern EF Core forbids and
        // the transformation has to unwind into a scoped, injected context.
        public static readonly ScoreboardContext Current = new ScoreboardContext();

        public ScoreboardContext() : base("name=ScoreboardContext")
        {
        }

        public DbSet<Team> Teams { get; set; }

        protected override void OnModelCreating(DbModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Team>()
                .Property(t => t.Name)
                .HasColumnAnnotation("Index", new System.Data.Entity.Infrastructure.Annotations.IndexAnnotation(
                    new IndexAttribute("IX_Team_Name") { IsUnique = true }));

            base.OnModelCreating(modelBuilder);
        }
    }
}
