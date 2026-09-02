using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ContosoScoreboard.Web.Models
{
    [Table("Teams")]
    public class Team
    {
        [Key]
        public int TeamId { get; set; }

        [Required]
        [StringLength(64)]
        public string Name { get; set; }

        [StringLength(2)]
        public string CountryCode { get; set; }

        public int Score { get; set; }

        [Column(TypeName = "datetime2")]
        public DateTime LastCaptureUtc { get; set; }

        public bool IsDisqualified { get; set; }
    }
}
