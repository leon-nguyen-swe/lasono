package archfixture.track.presentation;

import archfixture.track.application.ApplicationFixtures;
import archfixture.track.domain.DomainFixtures;
import archfixture.track.infrastructure.InfrastructureFixtures;

/**
 * Presentation classes that break the architecture rules on purpose. See {@code DomainFixtures}.
 */
public final class PresentationFixtures {

    private PresentationFixtures() {
    }

    /** A presentation class that follows the rules: it may use the application and the domain. */
    public static class Clean {
        ApplicationFixtures.Clean application;
        DomainFixtures.Clean domain;
    }

    public static class DependsOnInfrastructure {
        InfrastructureFixtures.Clean infrastructure;
    }
}
