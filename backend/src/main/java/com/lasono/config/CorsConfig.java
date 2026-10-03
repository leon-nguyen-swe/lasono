package com.lasono.config;

import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

@Configuration
public class CorsConfig {

    // A servlet filter (not WebMvcConfigurer#addCorsMappings) so that responses produced
    // outside the handler chain, such as multipart size errors, still carry CORS headers.
    @Bean
    public CorsFilter corsFilter(
        @Value("${lasono.cors.allowed-origins:http://localhost:3000,http://127.0.0.1:3000}") List<String> allowedOrigins
    ) {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(allowedOrigins);
        configuration.setAllowedMethods(List.of("GET", "POST", "OPTIONS"));
        configuration.setAllowedHeaders(List.of("*"));
        configuration.setExposedHeaders(List.of(
            HttpHeaders.CONTENT_RANGE,
            HttpHeaders.ACCEPT_RANGES,
            HttpHeaders.CONTENT_LENGTH
        ));

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", configuration);
        return new CorsFilter(source);
    }
}
