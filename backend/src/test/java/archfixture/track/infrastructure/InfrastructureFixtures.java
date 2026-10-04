package archfixture.track.infrastructure;

import archfixture.track.application.ApplicationFixtures;
import archfixture.track.domain.DomainFixtures;

/**
 * Infrastructure classes used by the architecture rule tests. See {@code DomainFixtures}.
 */
public final class InfrastructureFixtures {

    private InfrastructureFixtures() {
    }

    /** An infrastructure class that follows the rules: it may use the application and the domain. */
    public static class Clean {
        ApplicationFixtures.Clean application;
        DomainFixtures.Clean domain;
    }
}
