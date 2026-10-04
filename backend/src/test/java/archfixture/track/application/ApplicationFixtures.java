package archfixture.track.application;

import archfixture.track.domain.DomainFixtures;
import archfixture.track.infrastructure.InfrastructureFixtures;
import archfixture.track.presentation.PresentationFixtures;

/**
 * Application classes that break the architecture rules on purpose. See {@code DomainFixtures}.
 */
public final class ApplicationFixtures {

    private ApplicationFixtures() {
    }

    /** An application class that follows the rules: it may use the domain. */
    public static class Clean {
        DomainFixtures.Clean domain;
    }

    public static class DependsOnPresentation {
        PresentationFixtures.Clean presentation;
    }

    public static class DependsOnInfrastructure {
        InfrastructureFixtures.Clean infrastructure;
    }
}
