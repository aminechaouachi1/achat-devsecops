package tn.esprit.achat.services;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import tn.esprit.achat.entities.Produit;
import tn.esprit.achat.repositories.ProduitRepository;

@ExtendWith(MockitoExtension.class)
class ProduitServiceTest {

    @Mock
    private ProduitRepository repository;

    @InjectMocks
    private ProduitService service;

    @Test
    void findAllRetourneLesProduits() {
        when(repository.findAll()).thenReturn(List.of(new Produit("P1", "Stylo", 1.5, 100)));
        assertEquals(1, service.findAll().size());
    }

    @Test
    void createIgnoreLIdFourni() {
        Produit p = new Produit("P2", "Cahier", 3.0, 50);
        p.setId(99L);
        when(repository.save(any(Produit.class))).thenAnswer(i -> i.getArgument(0));
        assertNull(service.create(p).getId());
    }

    @Test
    void updateModifieLesChamps() {
        Produit existant = new Produit("P3", "Gomme", 0.5, 10);
        existant.setId(3L);
        when(repository.findById(3L)).thenReturn(Optional.of(existant));
        when(repository.save(any(Produit.class))).thenAnswer(i -> i.getArgument(0));

        Produit maj = service.update(3L, new Produit("P3", "Gomme blanche", 0.7, 20));

        assertEquals("Gomme blanche", maj.getLibelle());
        assertEquals(20, maj.getStock());
    }

    @Test
    void findByIdInconnuLeveUneException() {
        when(repository.findById(42L)).thenReturn(Optional.empty());
        assertThrows(NoSuchElementException.class, () -> service.findById(42L));
    }

    @Test
    void deleteSupprimeLeProduit() {
        Produit p = new Produit("P4", "Regle", 2.0, 5);
        when(repository.findById(4L)).thenReturn(Optional.of(p));
        service.delete(4L);
        verify(repository).delete(p);
    }
}
