package tn.esprit.achat.repositories;

import org.springframework.data.jpa.repository.JpaRepository;
import tn.esprit.achat.entities.Produit;

public interface ProduitRepository extends JpaRepository<Produit, Long> { }
