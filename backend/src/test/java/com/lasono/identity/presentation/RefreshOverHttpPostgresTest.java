package com.lasono.identity.presentation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import jakarta.servlet.http.Cookie;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;

import com.jayway.jsonpath.JsonPath;
import com.lasono.PostgresIntegrationTest;

/**
 * Logs in, refreshes and logs out through the real HTTP stack down to PostgreSQL, then looks at the
 * {@code refresh_tokens} table itself. The use case tests run on fakes with no transaction, so only here can
 * it be shown that a revoke survives the 401 that follows it, and that the row lock stops a double exchange.
 */
@AutoConfigureMockMvc
class RefreshOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";
    private static final Pattern REFRESH_COOKIE = Pattern.compile("lasono_refresh=([^;]*)");

    @Autowired
    private MockMvc mockMvc;

    @Test
    void aRefreshGivesNewTokensAndKeepsOnlyHashesInTheDatabase() throws Exception {
        register("alice@example.com");
        String firstCookie = cookieOf(login("alice@example.com"));

        MvcResult refreshed = refresh(firstCookie).andExpect(status().isOk()).andReturn();

        String secondCookie = cookieOf(refreshed);
        assertThat(secondCookie).isNotEmpty().isNotEqualTo(firstCookie);
        String newAccessToken = JsonPath.read(refreshed.getResponse().getContentAsString(), "$.accessToken");
        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + newAccessToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.email").value("alice@example.com"));

        List<Map<String, Object>> rows = tokenRows();
        assertThat(rows).hasSize(2);
        assertThat(rows.stream().map(row -> row.get("family_id")).distinct()).hasSize(1);
        assertThat(rows.stream().filter(row -> row.get("used_at") != null)).hasSize(1);
        assertThat(rows.stream().filter(row -> row.get("revoked_at") != null)).isEmpty();
        assertThat(rows.stream().map(row -> (String) row.get("token_hash")))
            .doesNotContain(firstCookie, secondCookie)
            .allMatch(hash -> hash.matches("[0-9a-f]{64}"));
    }

    @Test
    void theNewTokenCanBeExchangedAgainAndAgain() throws Exception {
        register("alice@example.com");
        String cookie = cookieOf(login("alice@example.com"));

        for (int i = 0; i < 3; i++) {
            cookie = cookieOf(refresh(cookie).andExpect(status().isOk()).andReturn());
        }

        assertThat(tokenRows()).hasSize(4);
        assertThat(tokenRows().stream().map(row -> row.get("family_id")).distinct()).hasSize(1);
    }

    // The 401 is thrown after the family is revoked. If the transaction rolled back on that exception, the
    // answer would still be 401 but the database would be unchanged, and the stolen family would stay alive.
    @Test
    void usingATokenAgainAnswers401AndTheRevokeOfTheWholeFamilyIsStillSaved() throws Exception {
        register("alice@example.com");
        String stolen = cookieOf(login("alice@example.com"));
        String newest = cookieOf(refresh(stolen).andExpect(status().isOk()).andReturn());

        refresh(stolen)
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid refresh token"));

        List<Map<String, Object>> rows = tokenRows();
        assertThat(rows).hasSize(2);
        assertThat(rows).allSatisfy(row -> assertThat(row.get("revoked_at")).isNotNull());
        refresh(newest).andExpect(status().isUnauthorized());
    }

    @Test
    void revokingOneFamilyLeavesAnotherSessionOfTheSameUserWorking() throws Exception {
        register("alice@example.com");
        String laptop = cookieOf(login("alice@example.com"));
        String phone = cookieOf(login("alice@example.com"));
        refresh(laptop).andExpect(status().isOk());

        refresh(laptop).andExpect(status().isUnauthorized());

        refresh(phone).andExpect(status().isOk());
    }

    @Test
    void afterALogoutTheCookieCannotBeExchangedAndTheFamilyIsRevoked() throws Exception {
        register("alice@example.com");
        String cookie = cookieOf(login("alice@example.com"));

        mockMvc.perform(post("/api/v1/auth/logout").cookie(new Cookie("lasono_refresh", cookie)))
            .andExpect(status().isNoContent());

        refresh(cookie).andExpect(status().isUnauthorized());
        assertThat(tokenRows()).allSatisfy(row -> assertThat(row.get("revoked_at")).isNotNull());
    }

    // Two requests carry the same token at the same moment. Without the row lock both could read it as unused
    // and both would be given a new token. With it, the second waits, finds the token used, and the family is revoked.
    @Test
    void twoExchangesOfTheSameTokenAtTheSameMomentCannotBothSucceed() throws Exception {
        register("alice@example.com");
        String cookie = cookieOf(login("alice@example.com"));
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch go = new CountDownLatch(1);
        try {
            List<Future<Integer>> answers = new ArrayList<>();
            for (int i = 0; i < 2; i++) {
                answers.add(executor.submit(() -> {
                    go.await(5, TimeUnit.SECONDS);
                    return refresh(cookie).andReturn().getResponse().getStatus();
                }));
            }
            go.countDown();

            List<Integer> statuses = new ArrayList<>();
            for (Future<Integer> answer : answers) {
                statuses.add(answer.get(20, TimeUnit.SECONDS));
            }

            assertThat(statuses).containsExactlyInAnyOrder(200, 401);
            // The old token and one new token only: the loser was refused and was given nothing.
            assertThat(tokenRows()).hasSize(2);
        } finally {
            executor.shutdownNow();
        }
    }

    private List<Map<String, Object>> tokenRows() {
        return jdbcTemplate.queryForList(
            "SELECT token_hash, family_id, used_at, revoked_at FROM refresh_tokens ORDER BY created_at");
    }

    private void register(String email) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"displayName\":\"Alice\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isCreated());
    }

    private MvcResult login(String email) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isOk())
            .andReturn();
    }

    private ResultActions refresh(String cookie) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("lasono_refresh", cookie)));
    }

    private static String cookieOf(MvcResult result) {
        Matcher matcher = REFRESH_COOKIE.matcher(result.getResponse().getHeader(HttpHeaders.SET_COOKIE));
        assertThat(matcher.find()).as("a lasono_refresh cookie in Set-Cookie").isTrue();
        return matcher.group(1);
    }
}
