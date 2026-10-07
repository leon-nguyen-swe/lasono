package archfixture.beta;

/** A class of a pretend module "beta" that module "alpha" must not depend on. See {@code AlphaFixtures}. */
public final class BetaFixtures {

    private BetaFixtures() {
    }

    public static class Clean {
        String id;
    }
}
