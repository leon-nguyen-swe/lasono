package archfixture.shared;

import java.time.Instant;
import java.util.UUID;

import archfixture.alpha.AlphaFixtures;

/**
 * Classes of a pretend shared kernel, used to prove the rule that the shared kernel
 * must not import any module or framework class.
 */
public final class SharedFixtures {

    private SharedFixtures() {
    }

    /** A shared class that follows the rule: only uses java.time and java.util. */
    public static class Clean {
        UUID id;
        Instant occurredAt;
    }

    /** A shared class that breaks the rule: imports a module class. */
    public static class ImportsAModule {
        AlphaFixtures.Clean module;
    }
}
