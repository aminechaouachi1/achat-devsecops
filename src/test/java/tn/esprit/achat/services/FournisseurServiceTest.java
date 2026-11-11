package tn.esprit.achat.services;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import java.util.NoSuchElementException;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import tn.esprit.achat.entities.Fournisseur;
import tn.esprit.achat.repositories.FournisseurRepository;

@ExtendWith(MockitoExtension.class)
class FournisseurServiceTest {

    @Mock
    private FournisseurRepository repository;

    @InjectMocks
    private FournisseurService service;

    @Test
    void createEnregistreLeFournisseur() {
        when(repository.save(any(Fournisseur.class))).thenAnswer(i -> i.getArgument(0));
        Fournisseur f = service.create(new Fournisseur("ACME", "contact@acme.tn"));
        assertEquals("ACME", f.getNom());
    }

    @Test
    void findByIdInconnuLeveUneException() {
        when(repository.findById(7L)).thenReturn(Optional.empty());
        assertThrows(NoSuchElementException.class, () -> service.findById(7L));
    }
}
