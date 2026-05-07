async function fetchWithAuth(url, options = {}) {
  let res = await fetch(url, {
    ...options,
    headers: {
      ...options.headers,
      Authorization: localStorage.accessToken
    }
  });
async function logout() {
  try {
    await fetch("/api/auth/logout", {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({
        refreshToken: localStorage.refreshToken
      })
    });
  } catch (e) {
    console.log("Logout error:", e);
  }

  // xóa token local
  localStorage.removeItem("accessToken");
  localStorage.removeItem("refreshToken");

  // redirect về login
  window.location.href = "/";
}

  if (res.status === 403) {
    const refresh = await fetch("/api/auth/refresh", {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({
        refreshToken: localStorage.refreshToken
      })
    });

    const data = await refresh.json();
    localStorage.accessToken = data.accessToken;

    return fetchWithAuth(url, options);
  }

  return res;
}