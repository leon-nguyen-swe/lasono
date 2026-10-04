package com.lasono.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.lang.ArchRule;

/**
 * The architecture rules from PROJECT_STATUS.md. Each rule takes the root package of a module, so
 * the same rule runs on the real code ({@code ArchitectureTest}) and on deliberately broken
 * classes ({@code ArchitectureRulesTest}).
 */
public final class ArchitectureRules {

    private ArchitectureRules() {
    }

    /** Domain must not depend on Spring, JPA, PostgreSQL (JDBC), the file system or HTTP. */
    public static ArchRule domainIsFrameworkFree(String root) {
        return noClasses().that().resideInAPackage(domain(root))
            .should().dependOnClassesThat().resideInAnyPackage(
                "org.springframework..",
                "jakarta.persistence..",
                "org.hibernate..",
                "java.sql..",
                "javax.sql..",
                "java.nio.file..",
                "java.io..",
                "java.net..",
                "jakarta.servlet..")
            .because("the domain must not depend on Spring, JPA, JDBC, the file system or HTTP");
    }

    /** Dependencies point inward: the domain knows none of the layers around it. */
    public static ArchRule domainDoesNotDependOnOtherLayers(String root) {
        return noClasses().that().resideInAPackage(domain(root))
            .should().dependOnClassesThat().resideInAnyPackage(
                root + "..application..",
                root + "..infrastructure..",
                root + "..presentation..")
            .because("dependencies must point inward: domain <- application <- presentation");
    }

    /** Presentation sits on top of application, never the other way around. */
    public static ArchRule applicationDoesNotDependOnPresentation(String root) {
        return noClasses().that().resideInAPackage(root + "..application..")
            .should().dependOnClassesThat().resideInAPackage(root + "..presentation..")
            .because("the application layer must not know about HTTP controllers");
    }

    /** Infrastructure implements the ports; no other layer may reference its classes directly. */
    public static ArchRule onlyInfrastructureUsesInfrastructure(String root) {
        return noClasses().that().resideOutsideOfPackage(root + "..infrastructure..")
            .should().dependOnClassesThat().resideInAPackage(root + "..infrastructure..")
            .because("other layers must depend on ports, and infrastructure implements them");
    }

    private static String domain(String root) {
        return root + "..domain..";
    }
}
