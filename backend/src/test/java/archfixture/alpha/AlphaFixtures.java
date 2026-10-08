package archfixture.alpha;

import archfixture.beta.BetaFixtures;

/**
 * Classes of a pretend module "alpha", used to prove the rule that one module must not depend on another.
 * See {@code DomainFixtures} for the same idea applied to the layers inside a module.
 */
public final class AlphaFixtures {

    private AlphaFixtures() {
    }

    /** An alpha class that follows the rule: it knows nothing about module beta. */
    public static class Clean {
        String id;
    }

    /** An alpha class that breaks the rule on purpose. */
    public static class DependsOnBeta {
        BetaFixtures.Clean other;
    }
}
