<template>
  <header class="appbar">
    <nav>
      <RouterLink to="/">Picks</RouterLink>
      <RouterLink to="/leaderboard">Leaderboard</RouterLink>
      <RouterLink to="/profile">Profile</RouterLink>
    </nav>
  </header>
  <main><slot /></main>
</template>
