#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
source src/language.sh
source src/input.sh
source src/validate.sh
source src/sni_stack_health.sh
source src/diagnostics_network.sh
CYAN='' GREEN='' YELLOW='' RED='' PLAIN=''
SUB_LISTEN_ADDR='127.0.0.1'
SUB_LISTEN_PORT='2096'
mock_code=200 mock_rc=0 mock_backend_code=200 mock_backend_rc=0 mock_redirects=0

curl() {
    if [[ "${*: -1}" == http://* ]]; then
        printf '%s' "$mock_backend_code"
        return "$mock_backend_rc"
    fi
    printf '%s' "$mock_code"
    [[ "$*" != *'%{num_redirects}'* ]] || printf ' %s' "$mock_redirects"
    return "$mock_rc"
}

for VPSO_LANGUAGE in zh en ru; do
    mock_code=404
    for prefix in /sub/ /clash/; do
        output=$(curl_sni_path_probe 'subscription' panel.example.com 443 "$prefix" subscription-prefix)
        [[ "$output" == *'ℹ️'* && "$output" == *'HTTP 404'* && "$output" == *'Sub ID'* ]]
        [[ "$output" != *'✅'* && "$output" != *'❌'* && "$output" != *'⚠️'* ]]
        health_output=$(print_web_domain_http_status 'subscription' panel.example.com "$prefix" subscription-prefix)
        [[ "$health_output" == *'ℹ️'* && "$health_output" == *'Sub ID'* ]]
        [[ "$health_output" != *'✅'* && "$health_output" != *'❌'* && "$health_output" != *'⚠️'* ]]
    done

    # Use synthetic IDs only, and check that no full subscription URL is printed.
    full_path='/sub/mock-sub-id-not-a-secret?hwid=mock-device'
    mock_code=200
    output=$(curl_sni_path_probe 'subscription' panel.example.com 443 "$full_path" subscription)
    [[ "$output" == *'✅'* && "$output" == *'HTTP 200'* ]]
    [[ "$output" != *'mock-sub-id'* && "$output" != *'mock-device'* && "$output" != *'https://'* ]]

    mock_code=404 mock_backend_code=404
    output=$(curl_sni_path_probe 'subscription' panel.example.com 443 "$full_path" subscription)
    [[ "$output" == *'⚠️'* && "$output" == *'HTTP 404'* && "$output" == *'HWID'* ]]
    [[ "$output" != *'❌'* && "$output" != *'✅'* && "$output" != *'mock-sub-id'* && "$output" != *'mock-device'* ]]

    mock_backend_code=200
    output=$(curl_sni_path_probe 'subscription' panel.example.com 443 "$full_path" subscription)
    [[ "$output" == *'❌'* && "$output" == *'200'* && "$output" == *'HTTP 404'* ]]
    [[ "$output" != *'mock-sub-id'* && "$output" != *'mock-device'* && "$output" != *'https://'* ]]

    mock_backend_code=000 mock_backend_rc=28
    output=$(curl_sni_path_probe 'subscription' panel.example.com 443 "$full_path" subscription)
    [[ "$output" == *'❌'* && "$output" == *'curl exit 28'* && "$output" == *'HWID'* ]]
    [[ "$output" != *'mock-sub-id'* && "$output" != *'mock-device'* ]]
    mock_backend_code=200 mock_backend_rc=0

    for mock_code in 500 502 503; do
        # HTTP response exit codes remain 0 even when the result reports an error.
        output=$(curl_sni_path_probe 'subscription' panel.example.com 443 /sub/ subscription-prefix)
        [[ "$output" == *'❌'* && "$output" == *"HTTP ${mock_code}"* && "$output" != *'✅'* ]]
        health_output=$(print_web_domain_http_status 'subscription' panel.example.com /sub/ subscription-prefix)
        [[ "$health_output" == *'❌'* && "$health_output" != *'✅'* ]]
    done
    for mock_code in 301 302 307 401 403 429 100; do
        output=$(curl_sni_path_probe 'panel' panel.example.com 443 /panel/)
        [[ "$output" == *'⚠️'* && "$output" == *"HTTP ${mock_code}"* && "$output" != *'✅'* ]]
        health_output=$(print_web_domain_http_status 'panel' panel.example.com /panel/)
        [[ "$health_output" == *'⚠️'* && "$health_output" != *'✅'* ]]
    done

    mock_code=000
    for mock_rc in 0 7 28 35 60; do
        if output=$(curl_sni_path_probe 'subscription' panel.example.com 443 "$full_path" subscription); then
            echo "Transport failure must return 1 (${VPSO_LANGUAGE}, curl ${mock_rc})." >&2
            exit 1
        else
            [[ "$?" == 1 ]]
        fi
        [[ "$output" == *'❌'* && "$output" == *"curl exit ${mock_rc}"* && "$output" != *'mock-sub-id'* && "$output" != *'mock-device'* ]]
        # The status-display helper retains its original non-fatal exit code.
        health_output=$(print_web_domain_http_status 'panel' panel.example.com /panel/)
        [[ "$health_output" == *'❌'* && "$health_output" == *"curl exit ${mock_rc}"* ]]
    done
    mock_rc=0 mock_code=200
    output=$(curl_sni_path_probe 'panel' panel.example.com 443 /panel/)
    [[ "$output" == *'✅'* && "$output" == *'https://panel.example.com/panel/'* ]]
    mock_code=404
    output=$(curl_sni_path_probe 'panel' panel.example.com 443 /panel/)
    [[ "$output" == *'⚠️'* && "$output" != *'ℹ️'* && "$output" == *'HTTP 404'* ]]

    mock_code=200 mock_redirects=1
    health_output=$(print_web_domain_http_status 'panel' panel.example.com /panel/)
    [[ "$health_output" == *'HTTP 200'* && "$health_output" == *'⚠️'* ]]
    mock_redirects=0
done

for file in src/diagnostics_network.sh src/sni_stack_health.sh; do
    grep -Fq '"$SUB_URI_PATH" subscription-prefix' "$file"
    grep -Fq '"$CLASH_URI_PATH" subscription-prefix' "$file"
done
echo "HTTP probe regression tests passed (zh/en/ru)."
