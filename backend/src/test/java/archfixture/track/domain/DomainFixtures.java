package archfixture.track.domain;

import java.io.InputStream;
import java.net.http.HttpClient;
import java.nio.file.Path;
import java.sql.Connection;
import java.util.List;

import org.hibernate.Session;
import org.springframework.stereotype.Component;

import archfixture.track.application.ApplicationFixtures;
import archfixture.track.infrastructure.InfrastructureFixtures;
import archfixture.track.presentation.PresentationFixtures;

import jakarta.persistence.Entity;
import jakarta.servlet.http.HttpServletRequest;

/**
 * Domain classes that break the architecture rules on purpose. They only exist to prove that the
 * rules in {@code ArchitectureRules} really fail when someone breaks them.
 */
public final class DomainFixtures {

    private DomainFixtures() {
    }

    /** A domain class that follows the rules. */
    public static class Clean {
        List<String> names;
    }

    @Component
    public static class UsesSpring {
    }

    @Entity
    public static class UsesJpa {
    }

    public static class UsesHibernate {
        Session session;
    }

    public static class UsesFileSystem {
        Path path;
    }

    public static class UsesIo {
        InputStream stream;
    }

    public static class UsesHttp {
        HttpClient client;
    }

    public static class UsesJdbc {
        Connection connection;
    }

    public static class UsesServlet {
        HttpServletRequest request;
    }

    public static class DependsOnApplication {
        ApplicationFixtures.Clean application;
    }

    public static class DependsOnInfrastructure {
        InfrastructureFixtures.Clean infrastructure;
    }

    public static class DependsOnPresentation {
        PresentationFixtures.Clean presentation;
    }
}
