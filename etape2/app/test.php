<?php
// Affiche les erreurs mysqli clairement
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    // ⚠️ Identifiants qu’on a définis au lancement de MariaDB
    $mysqli = new mysqli('data', 'tp3', 'tp3pass', 'tp3');
    $mysqli->set_charset('utf8mb4');

    // 1) Assurer que la table existe (créée si absente)
    $mysqli->query("
        CREATE TABLE IF NOT EXISTS matable (
            id INT AUTO_INCREMENT PRIMARY KEY,
            compteur INT NOT NULL
        )
    ");

    // 2) Écriture : insère compteur = (max existant + 1)
    $mysqli->query("
        INSERT INTO matable (compteur)
        SELECT COALESCE(MAX(compteur), 0) + 1 FROM matable
    ");

    // 3) Lecture : compter les lignes (et afficher la dernière valeur)
    $res = $mysqli->query("SELECT compteur FROM matable ORDER BY id DESC LIMIT 1");
    $last = $res->fetch_assoc()['compteur'] ?? 0;
    $res->close();

    $res2 = $mysqli->query("SELECT COUNT(*) AS n FROM matable");
    $n = $res2->fetch_assoc()['n'] ?? 0;
    $res2->close();

    printf("Dernier compteur : %d<br />", $last);
    printf("Nombre de lignes : %d<br />", $n);

} catch (mysqli_sql_exception $e) {
    echo "Erreur MySQL : " . $e->getMessage();
} finally {
    if (isset($mysqli) && $mysqli instanceof mysqli) {
        $mysqli->close();
    }
}
