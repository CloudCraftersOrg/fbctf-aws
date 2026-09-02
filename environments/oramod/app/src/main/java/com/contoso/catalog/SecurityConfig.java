package com.contoso.catalog;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.authentication.builders.AuthenticationManagerBuilder;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configuration.WebSecurityConfigurerAdapter;

// WebSecurityConfigurerAdapter was removed in Spring Security 6 / Spring Boot 3.
// The Transform Java agent rewrites this to a SecurityFilterChain + a
// UserDetailsService @Bean.
@Configuration
@EnableWebSecurity
public class SecurityConfig extends WebSecurityConfigurerAdapter {

    @Value("${catalog.editor-password:editor}")
    private String editorPassword;

    @Override
    protected void configure(AuthenticationManagerBuilder auth) throws Exception {
        auth.inMemoryAuthentication()
            .withUser("editor")
            .password("{noop}" + editorPassword)
            .roles("EDITOR");
    }

    @Override
    protected void configure(HttpSecurity http) throws Exception {
        http
            .csrf().disable()
            .authorizeRequests()
                .antMatchers("/", "/api/**", "/webjars/**", "/css/**").permitAll()
                .antMatchers("/products", "/restock").hasRole("EDITOR")
                .anyRequest().permitAll()
            .and()
            .httpBasic();
    }
}
