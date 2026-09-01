# java-catalog — Java 8 → 17 modernization fixture

The challenge-catalog service (`catalog-svc-01` in the inventory): Spring Boot
2.3 on Java 8, Maven, packaged as a WAR for an external Tomcat.

## Why this forces a real transformation

| Construct | Where | What the agent must do |
|---|---|---|
| `java.version` = 1.8, Spring Boot 2.3.x | `pom.xml` | bump to Java 17 + Spring Boot 3.x |
| `javax.persistence.*`, `javax.validation.*` | `domain/Challenge.java` | rewrite to `jakarta.*` |
| `WebSecurityConfigurerAdapter` | `config/SecurityConfig.java` | migrate to the component-based `SecurityFilterChain` |
| `WebMvcConfigurerAdapter` deprecated base | `config/SecurityConfig.java` | implement the interface directly |
| `Date` + `SimpleDateFormat` (not thread-safe) | `service/ScoreClient.java` | `java.time` |
| `RestTemplate` | `service/ScoreClient.java` | flagged for `WebClient` / `RestClient` |
| JUnit 4 (`@RunWith`, `junit:junit`) | `src/test/...` | JUnit 5 |
| WAR packaging + `SpringBootServletInitializer` | `pom.xml`, `CatalogApplication` | executable JAR / container |
| `maven-compiler-plugin` pinned old | `pom.xml` | toolchain refresh |

## Target

`Java 17`, Spring Boot 3, executable JAR in a container, for `catalog-svc-01`
(also an OS end-of-support host — RHEL 7).
