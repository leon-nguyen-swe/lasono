package com.lasono.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            // The API will authenticate with an "Authorization: Bearer ..." header, which a browser never adds
            // by itself, so a forged cross-site form cannot use it and CSRF protection is not needed.
            .csrf(csrf -> csrf.disable())
            // Security runs before CorsFilter. This makes it use the corsFilter bean of CorsConfig,
            // otherwise the browser's preflight request would be refused before CORS is applied.
            .cors(Customizer.withDefaults())
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(requests -> requests
                .requestMatchers("/api/v1/auth/**").permitAll()
                // Temporary: open until uploading requires a login.
                .requestMatchers("/api/v1/tracks/**").permitAll()
                .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                // Everything else is closed unless a route above opens it.
                .anyRequest().authenticated())
            // Without this, Spring answers 403 to a caller who has not logged in; the right status is 401.
            .exceptionHandling(errors -> errors.authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)));

        return http.build();
    }
}
