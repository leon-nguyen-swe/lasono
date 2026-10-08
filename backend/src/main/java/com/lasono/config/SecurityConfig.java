package com.lasono.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.server.resource.web.BearerTokenResolver;
import org.springframework.security.oauth2.server.resource.web.DefaultBearerTokenResolver;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        ProblemDetailSecurityHandler problemDetails = new ProblemDetailSecurityHandler();

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
                // Reading is open until tracks can be private. Uploading, and later editing and deleting, need a
                // login: every other method falls through to the rule at the bottom.
                .requestMatchers(HttpMethod.GET, "/api/v1/tracks/**").permitAll()
                .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                // Everything else is closed unless a route above opens it.
                .anyRequest().authenticated())
            // Reads "Authorization: Bearer ...", checks it with the JwtDecoder bean and puts the user in the request.
            .oauth2ResourceServer(oauth2 -> oauth2
                .bearerTokenResolver(ignoreTokenOnPublicAuthRoutes())
                .jwt(Customizer.withDefaults())
                .authenticationEntryPoint(problemDetails)
                .accessDeniedHandler(problemDetails))
            // The same answers for requests that carry no token at all (401) or that are forbidden (403).
            .exceptionHandling(errors -> errors
                .authenticationEntryPoint(problemDetails)
                .accessDeniedHandler(problemDetails));

        return http.build();
    }

    // Once a token is sent, Spring checks it even on a public route. The app keeps sending its old token after it
    // has expired, and that must not make a login fail with "invalid token" when the password is what is wrong.
    // Login, register and refresh never need a token, so a token sent to them is simply not looked at.
    private static BearerTokenResolver ignoreTokenOnPublicAuthRoutes() {
        DefaultBearerTokenResolver standard = new DefaultBearerTokenResolver();
        return request -> request.getRequestURI().startsWith("/api/v1/auth/") ? null : standard.resolve(request);
    }
}
