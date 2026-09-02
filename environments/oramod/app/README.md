# Contoso Catalog — live Java 8 app on Oracle

The third app in the stack, and a three-way AWS Transform target:

| Path | What Transform does |
|---|---|
| **Java 8 → 17** | Spring Boot 2.7 → 3, `javax.persistence` → `jakarta`, `WebSecurityConfigurerAdapter` → `SecurityFilterChain`, `RestTemplate` → `RestClient`, `SimpleDateFormat` field → `java.time`, JUnit 4 → 5 |
| **Oracle → Aurora PostgreSQL** | `PRODUCT_SEQ` + `trg_products_bi` → identity/serial; `catalog_pkg` PL/SQL package → PL/pgSQL function; `VW_CATALOG_SUMMARY` view; `VIRTUAL` column; `... FROM dual` |
| **Data layer** | the JPA `@SequenceGenerator`, native `@Query` against `catalog_pkg.restock` and `VW_CATALOG_SUMMARY` rewritten alongside the schema |

Spring Boot MVC + Thymeleaf UI: product list, per-category summary (from the view),
add-product and restock (through the PL/SQL package). JSON at `/api/products`.

Built on the app host at boot from `app.zip` (staged in the artifacts bucket by
`archive_file`), run by systemd against `fbctf-oramod-oracle`.
