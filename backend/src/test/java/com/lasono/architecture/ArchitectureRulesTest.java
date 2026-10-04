package com.lasono.architecture;

import static com.lasono.architecture.ArchitectureRules.applicationDoesNotDependOnPresentation;
import static com.lasono.architecture.ArchitectureRules.domainDoesNotDependOnOtherLayers;
import static com.lasono.architecture.ArchitectureRules.domainIsFrameworkFree;
import static com.lasono.architecture.ArchitectureRules.onlyInfrastructureUsesInfrastructure;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.params.provider.Arguments.arguments;

import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

import archfixture.track.application.ApplicationFixtures;
import archfixture.track.domain.DomainFixtures;
import archfixture.track.infrastructure.InfrastructureFixtures;
import archfixture.track.presentation.PresentationFixtures;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.lang.ArchRule;

/**
 * A rule that never fails proves nothing. These tests feed each rule a class that breaks it on
 * purpose (see the {@code archfixture} package) and require the rule to fail, and feed it classes
 * that follow the rules and require it to pass.
 */
class ArchitectureRulesTest {

    private static final String FIXTURE_ROOT = "archfixture.track";

    static Stream<Arguments> violations() {
        return Stream.of(
            arguments("domain uses Spring (annotation)", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesSpring.class),
            arguments("domain uses JPA (annotation)", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesJpa.class),
            arguments("domain uses Hibernate", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesHibernate.class),
            arguments("domain uses the file system", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesFileSystem.class),
            arguments("domain uses java.io", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesIo.class),
            arguments("domain uses HTTP", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesHttp.class),
            arguments("domain uses JDBC", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesJdbc.class),
            arguments("domain uses the Servlet API", domainIsFrameworkFree(FIXTURE_ROOT), DomainFixtures.UsesServlet.class),
            arguments("domain depends on application", domainDoesNotDependOnOtherLayers(FIXTURE_ROOT), DomainFixtures.DependsOnApplication.class),
            arguments("domain depends on infrastructure", domainDoesNotDependOnOtherLayers(FIXTURE_ROOT), DomainFixtures.DependsOnInfrastructure.class),
            arguments("domain depends on presentation", domainDoesNotDependOnOtherLayers(FIXTURE_ROOT), DomainFixtures.DependsOnPresentation.class),
            arguments("application depends on presentation", applicationDoesNotDependOnPresentation(FIXTURE_ROOT), ApplicationFixtures.DependsOnPresentation.class),
            arguments("application depends on infrastructure", onlyInfrastructureUsesInfrastructure(FIXTURE_ROOT), ApplicationFixtures.DependsOnInfrastructure.class),
            arguments("presentation depends on infrastructure", onlyInfrastructureUsesInfrastructure(FIXTURE_ROOT), PresentationFixtures.DependsOnInfrastructure.class)
        );
    }

    @ParameterizedTest(name = "fails when {0}")
    @MethodSource("violations")
    void ruleFailsOnAClassThatBreaksIt(String description, ArchRule rule, Class<?> violating) {
        JavaClasses classes = new ClassFileImporter().importClasses(violating);

        // "was violated" separates a real violation from ArchUnit's "failed to check any classes",
        // which a mistyped package name would also raise and make this test pass for the wrong reason.
        assertThatThrownBy(() -> rule.check(classes))
            .isInstanceOf(AssertionError.class)
            .hasMessageContaining("was violated");
    }

    @Test
    void everyRulePassesOnClassesThatFollowTheRules() {
        JavaClasses classes = new ClassFileImporter().importClasses(
            DomainFixtures.Clean.class,
            ApplicationFixtures.Clean.class,
            InfrastructureFixtures.Clean.class,
            PresentationFixtures.Clean.class
        );

        assertThatCode(() -> {
            domainIsFrameworkFree(FIXTURE_ROOT).check(classes);
            domainDoesNotDependOnOtherLayers(FIXTURE_ROOT).check(classes);
            applicationDoesNotDependOnPresentation(FIXTURE_ROOT).check(classes);
            onlyInfrastructureUsesInfrastructure(FIXTURE_ROOT).check(classes);
        }).doesNotThrowAnyException();
    }
}
