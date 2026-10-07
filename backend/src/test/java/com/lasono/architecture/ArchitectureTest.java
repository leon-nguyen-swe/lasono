package com.lasono.architecture;

import static com.lasono.architecture.ArchitectureRules.applicationDoesNotDependOnPresentation;
import static com.lasono.architecture.ArchitectureRules.domainDoesNotDependOnOtherLayers;
import static com.lasono.architecture.ArchitectureRules.domainIsFrameworkFree;
import static com.lasono.architecture.ArchitectureRules.moduleDoesNotDependOn;
import static com.lasono.architecture.ArchitectureRules.onlyInfrastructureUsesInfrastructure;
import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;

/** Checks the real {@code track} and {@code identity} modules against the architecture rules. */
class ArchitectureTest {

    private static final String TRACK = "com.lasono.track";
    private static final String IDENTITY = "com.lasono.identity";

    private static JavaClasses classes;

    @BeforeAll
    static void importProductionClasses() {
        classes = new ClassFileImporter()
            .withImportOption(new ImportOption.DoNotIncludeTests())
            .importPackages(TRACK, IDENTITY);
    }

    @Test
    void identityClassesAreImported() {
        assertThat(classes.contain("com.lasono.identity.domain.User")).isTrue();
        assertThat(classes.contain("com.lasono.identity.application.usecase.RegisterUserUseCase")).isTrue();
        assertThat(classes.contain("com.lasono.identity.infrastructure.persistence.UserPersistenceAdapter")).isTrue();
        assertThat(classes.contain("com.lasono.identity.presentation.AuthController")).isTrue();
    }

    // D6: the modules hold each other's ids as plain values and never import each other's classes.
    @Test
    void trackDoesNotDependOnIdentity() {
        moduleDoesNotDependOn(TRACK, IDENTITY).check(classes);
    }

    @Test
    void identityDoesNotDependOnTrack() {
        moduleDoesNotDependOn(IDENTITY, TRACK).check(classes);
    }

    @Test
    void productionClassesAreImported() {
        assertThat(classes.contain("com.lasono.track.domain.Track")).isTrue();
        assertThat(classes.contain("com.lasono.track.application.usecase.GetTrackUseCase")).isTrue();
        assertThat(classes.contain("com.lasono.track.infrastructure.persistence.TrackPersistenceAdapter")).isTrue();
        assertThat(classes.contain("com.lasono.track.presentation.TrackController")).isTrue();
    }

    @Test
    void domainDoesNotUseFrameworksOrIo() {
        domainIsFrameworkFree(TRACK).check(classes);
        domainIsFrameworkFree(IDENTITY).check(classes);
    }

    @Test
    void domainIsIndependentOfTheOuterLayers() {
        domainDoesNotDependOnOtherLayers(TRACK).check(classes);
        domainDoesNotDependOnOtherLayers(IDENTITY).check(classes);
    }

    @Test
    void applicationIsIndependentOfPresentation() {
        applicationDoesNotDependOnPresentation(TRACK).check(classes);
        applicationDoesNotDependOnPresentation(IDENTITY).check(classes);
    }

    @Test
    void infrastructureIsUsedOnlyByItself() {
        onlyInfrastructureUsesInfrastructure(TRACK).check(classes);
        onlyInfrastructureUsesInfrastructure(IDENTITY).check(classes);
    }
}
